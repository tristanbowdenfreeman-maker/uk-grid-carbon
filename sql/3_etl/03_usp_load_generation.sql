-- Loads fact.national_mix from the generation windows not loaded yet (see usp_load_national).
CREATE OR ALTER PROCEDURE etl.usp_load_generation
    @windows_per_batch INT = 20
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
        WHERE source = 'generation' AND loaded_at IS NULL
        ORDER BY window_start;
        IF @@ROWCOUNT = 0 BREAK;

        DROP TABLE IF EXISTS #periods;
        SELECT TRY_CAST(LEFT(j.[from], 16) + ':00' AS DATETIME2(0)) AS period_start_utc,
               j.generationmix, b.window_start, b.window_end
        INTO #periods
        FROM @batch AS b
        JOIN stg.v_api_raw AS r ON r.source = 'generation' AND r.window_start = b.window_start
        CROSS APPLY OPENJSON(r.payload, '$.data') WITH (
            [from]         VARCHAR(20)   '$.from',
            generationmix  NVARCHAR(MAX) '$.generationmix' AS JSON
        ) AS j;

        DELETE #periods
        WHERE period_start_utc <  CAST(window_start AS DATETIME2(0))
           OR period_start_utc >= CAST(window_end AS DATETIME2(0));

        BEGIN TRANSACTION;
            DELETE f
            FROM fact.national_mix AS f
            JOIN @batch AS b ON f.period_start_utc >= CAST(b.window_start AS DATETIME2(0))
                            AND f.period_start_utc <  CAST(b.window_end AS DATETIME2(0));

            INSERT fact.national_mix (period_start_utc, fuel_id, date_key, half_hour, share_pct)
            SELECT p.period_start_utc, fu.fuel_id, uk.date_key, uk.half_hour, MAX(m.perc)
            FROM #periods AS p
            CROSS APPLY etl.fn_uk_time(p.period_start_utc) AS uk
            CROSS APPLY OPENJSON(p.generationmix) WITH (fuel VARCHAR(10) '$.fuel', perc DECIMAL(4, 1) '$.perc') AS m
            JOIN dim.fuel AS fu ON fu.fuel_key = m.fuel
            GROUP BY p.period_start_utc, fu.fuel_id, uk.date_key, uk.half_hour;
            SET @rows += @@ROWCOUNT;

            UPDATE r SET loaded_at = SYSUTCDATETIME()
            FROM stg.api_raw AS r JOIN @batch AS b ON r.source = 'generation' AND r.window_start = b.window_start;
        COMMIT;
    END;

    SELECT 'generation' AS source, @rows AS rows_loaded;
END;
GO
