-- Loads fact.price from the price windows not loaded yet. A window holds one part per Agile
-- version on sale during it, and each part one array of rates per region letter:
-- {"parts": [{"product": ..., "from": ..., "to": ..., "regions": {"A": [{"from": ..., "p": ...}]}}]}.
-- Each part only keeps rates inside its own dates, so versions never overlap.
CREATE OR ALTER PROCEDURE etl.usp_load_prices
    @windows_per_batch INT = 6
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @batch TABLE (window_start DATE PRIMARY KEY, window_end DATE NOT NULL);
    DECLARE @rows INT = 0;

    WHILE 1 = 1
    BEGIN
        DELETE @batch;
        INSERT @batch (window_start, window_end)
        SELECT TOP (@windows_per_batch) window_start, window_end
        FROM stg.api_raw
        WHERE source = 'prices' AND loaded_at IS NULL
        ORDER BY window_start;
        IF @@ROWCOUNT = 0 BREAK;

        DROP TABLE IF EXISTS #parsed;
        SELECT x.period_start_utc, x.region_id, x.price_p_kwh, x.product_code
        INTO #parsed
        FROM (
            SELECT TRY_CAST(LEFT(rate.[from], 16) + ':00' AS DATETIME2(0)) AS period_start_utc,
                   reg.region_id,
                   rate.p AS price_p_kwh,
                   part.product AS product_code,
                   part.part_from, part.part_to,
                   ROW_NUMBER() OVER (PARTITION BY rate.[from], reg.region_id ORDER BY b.window_start DESC) AS rn
            FROM @batch AS b
            JOIN stg.v_api_raw AS r ON r.source = 'prices' AND r.window_start = b.window_start
            CROSS APPLY OPENJSON(r.payload, '$.parts') WITH (
                product    VARCHAR(24)   '$.product',
                part_from  DATE          '$.from',
                part_to    DATE          '$.to',
                regions    NVARCHAR(MAX) '$.regions' AS JSON
            ) AS part
            CROSS APPLY OPENJSON(part.regions) AS letter          -- key = region letter, value = its rates
            JOIN dim.region AS reg ON reg.tariff_region = letter.[key] COLLATE DATABASE_DEFAULT  -- OPENJSON keys are BIN2
            CROSS APPLY OPENJSON(letter.[value]) WITH (
                [from]  VARCHAR(25)   '$.from',
                p       DECIMAL(7, 3) '$.p'
            ) AS rate
        ) AS x
        WHERE x.rn = 1
          AND x.period_start_utc >= CAST(x.part_from AS DATETIME2(0))
          AND x.period_start_utc <  CAST(x.part_to AS DATETIME2(0));

        BEGIN TRANSACTION;
            DELETE f
            FROM fact.price AS f
            JOIN @batch AS b ON f.period_start_utc >= CAST(b.window_start AS DATETIME2(0))
                            AND f.period_start_utc <  CAST(b.window_end AS DATETIME2(0));

            -- UK time once per half-hour, not once per region.
            DROP TABLE IF EXISTS #uk;
            SELECT t.period_start_utc, uk.date_key, uk.half_hour
            INTO #uk
            FROM (SELECT DISTINCT period_start_utc FROM #parsed) AS t
            CROSS APPLY etl.fn_uk_time(t.period_start_utc) AS uk;

            INSERT fact.price (period_start_utc, region_id, date_key, half_hour, price_p_kwh, product_code)
            SELECT p.period_start_utc, p.region_id, uk.date_key, uk.half_hour, p.price_p_kwh, p.product_code
            FROM #parsed AS p
            JOIN #uk AS uk ON uk.period_start_utc = p.period_start_utc;
            SET @rows += @@ROWCOUNT;

            UPDATE r SET loaded_at = SYSUTCDATETIME()
            FROM stg.api_raw AS r JOIN @batch AS b ON r.source = 'prices' AND r.window_start = b.window_start;
        COMMIT;
    END;

    SELECT 'prices' AS source, @rows AS rows_loaded;
END;
GO
