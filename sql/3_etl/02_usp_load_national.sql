-- Loads fact.national_intensity from the national windows not loaded yet, a few at a time.
-- Each window replaces its own half-hours, so a re-downloaded window (with actuals filled in)
-- simply overwrites them. A window's payload also holds the half-hour before it starts, which
-- belongs to the previous window, so only periods inside [window_start, window_end) are kept.
CREATE OR ALTER PROCEDURE etl.usp_load_national
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
        WHERE source = 'national' AND loaded_at IS NULL
        ORDER BY window_start;
        IF @@ROWCOUNT = 0 BREAK;

        DROP TABLE IF EXISTS #parsed;
        -- The source has a few impossible values (2018-19 forecasts up to 13,579 g): blank them.
        SELECT p.period_start_utc,
               CASE WHEN p.forecast BETWEEN 0 AND 1000 THEN p.forecast END AS forecast,
               CASE WHEN p.actual   BETWEEN 0 AND 1000 THEN p.actual   END AS actual,
               p.intensity_index
        INTO #parsed
        FROM (
            SELECT TRY_CAST(LEFT(j.[from], 16) + ':00' AS DATETIME2(0)) AS period_start_utc,
                   j.forecast, j.actual, j.intensity_index, b.window_start, b.window_end,
                   ROW_NUMBER() OVER (PARTITION BY j.[from] ORDER BY b.window_start DESC) AS rn
            FROM @batch AS b
            JOIN stg.v_api_raw AS r ON r.source = 'national' AND r.window_start = b.window_start
            CROSS APPLY OPENJSON(r.payload, '$.data') WITH (
                [from]           VARCHAR(20) '$.from',
                forecast         SMALLINT    '$.intensity.forecast',
                actual           SMALLINT    '$.intensity.actual',
                intensity_index  VARCHAR(10) '$.intensity.index'
            ) AS j
        ) AS p
        WHERE p.rn = 1
          AND p.period_start_utc >= CAST(p.window_start AS DATETIME2(0))
          AND p.period_start_utc <  CAST(p.window_end AS DATETIME2(0));
        -- A timestamp format the parse doesn't know would otherwise load nothing, silently.
        IF NOT EXISTS (SELECT 1 FROM #parsed)
            THROW 50001, 'usp_load_national: no half-hours parsed from this batch', 1;

        BEGIN TRANSACTION;
            DELETE f
            FROM fact.national_intensity AS f
            JOIN @batch AS b ON f.period_start_utc >= CAST(b.window_start AS DATETIME2(0))
                            AND f.period_start_utc <  CAST(b.window_end AS DATETIME2(0));

            INSERT fact.national_intensity (period_start_utc, period_start_uk, date_key, half_hour,
                                            forecast, actual, intensity_index)
            SELECT p.period_start_utc, uk.period_start_uk, uk.date_key, uk.half_hour,
                   p.forecast, p.actual, p.intensity_index
            FROM #parsed AS p
            CROSS APPLY etl.fn_uk_time(p.period_start_utc) AS uk;
            SET @rows += @@ROWCOUNT;

            UPDATE r SET loaded_at = SYSUTCDATETIME()
            FROM stg.api_raw AS r JOIN @batch AS b ON r.source = 'national' AND r.window_start = b.window_start;
        COMMIT;
    END;

    SELECT 'national' AS source, @rows AS rows_loaded;
END;
GO
