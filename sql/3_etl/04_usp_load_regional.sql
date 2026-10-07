-- Loads fact.regional_intensity and fact.regional_mix from the regional windows not loaded yet
-- (see usp_load_national). UK local time is worked out once per half-hour, not once per row:
-- the mix has 162 rows per half-hour.
CREATE OR ALTER PROCEDURE etl.usp_load_regional
    @windows_per_batch INT = 10
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
        WHERE source = 'regional' AND loaded_at IS NULL
        ORDER BY window_start;
        IF @@ROWCOUNT = 0 BREAK;

        DROP TABLE IF EXISTS #regions;
        SELECT TRY_CAST(LEFT(j.[from], 16) + ':00' AS DATETIME2(0)) AS period_start_utc,
               reg.region_id, reg.intensity, reg.intensity_index, reg.generationmix,
               b.window_start, b.window_end
        INTO #regions
        FROM @batch AS b
        JOIN stg.v_api_raw AS r ON r.source = 'regional' AND r.window_start = b.window_start
        CROSS APPLY OPENJSON(r.payload, '$.data') WITH (
            [from]   VARCHAR(20)   '$.from',
            regions  NVARCHAR(MAX) '$.regions' AS JSON
        ) AS j
        CROSS APPLY OPENJSON(j.regions) WITH (
            region_id        TINYINT       '$.regionid',
            intensity        SMALLINT      '$.intensity.forecast',
            intensity_index  VARCHAR(10)   '$.intensity.index',
            generationmix    NVARCHAR(MAX) '$.generationmix' AS JSON
        ) AS reg;

        DELETE #regions
        WHERE period_start_utc <  CAST(window_start AS DATETIME2(0))
           OR period_start_utc >= CAST(window_end AS DATETIME2(0))
           OR intensity IS NULL
           OR intensity NOT BETWEEN 0 AND 1000;   -- the source has a few negative estimates (London, 2018-20)

        DROP TABLE IF EXISTS #uk;
        SELECT p.period_start_utc, uk.date_key, uk.half_hour
        INTO #uk
        FROM (SELECT DISTINCT period_start_utc FROM #regions) AS p
        CROSS APPLY etl.fn_uk_time(p.period_start_utc) AS uk;

        BEGIN TRANSACTION;
            DELETE f
            FROM fact.regional_intensity AS f
            JOIN @batch AS b ON f.period_start_utc >= CAST(b.window_start AS DATETIME2(0))
                            AND f.period_start_utc <  CAST(b.window_end AS DATETIME2(0));
            DELETE f
            FROM fact.regional_mix AS f
            JOIN @batch AS b ON f.period_start_utc >= CAST(b.window_start AS DATETIME2(0))
                            AND f.period_start_utc <  CAST(b.window_end AS DATETIME2(0));

            INSERT fact.regional_intensity (period_start_utc, region_id, date_key, half_hour, intensity, intensity_index)
            SELECT r.period_start_utc, r.region_id, uk.date_key, uk.half_hour, MAX(r.intensity), MAX(r.intensity_index)
            FROM #regions AS r
            JOIN #uk AS uk ON uk.period_start_utc = r.period_start_utc
            GROUP BY r.period_start_utc, r.region_id, uk.date_key, uk.half_hour;
            SET @rows += @@ROWCOUNT;

            INSERT fact.regional_mix (period_start_utc, region_id, fuel_id, date_key, half_hour, share_pct)
            SELECT r.period_start_utc, r.region_id, fu.fuel_id, uk.date_key, uk.half_hour, MAX(m.perc)
            FROM #regions AS r
            JOIN #uk AS uk ON uk.period_start_utc = r.period_start_utc
            CROSS APPLY OPENJSON(r.generationmix) WITH (fuel VARCHAR(10) '$.fuel', perc DECIMAL(4, 1) '$.perc') AS m
            JOIN dim.fuel AS fu ON fu.fuel_key = m.fuel
            GROUP BY r.period_start_utc, r.region_id, fu.fuel_id, uk.date_key, uk.half_hour;
            SET @rows += @@ROWCOUNT;

            UPDATE r SET loaded_at = SYSUTCDATETIME()
            FROM stg.api_raw AS r JOIN @batch AS b ON r.source = 'regional' AND r.window_start = b.window_start;
        COMMIT;
    END;

    SELECT 'regional' AS source, @rows AS rows_loaded;
END;
GO
