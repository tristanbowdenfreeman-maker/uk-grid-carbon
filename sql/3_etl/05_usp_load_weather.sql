-- Loads fact.weather_hourly from the weather windows (one calendar month each) not loaded yet.
-- Open-Meteo returns one object per weather point, in the order of dim.weather_point, each
-- holding parallel arrays: hourly.time[i] goes with hourly.wind_speed_100m[i] and so on. Each
-- array is unpacked into its own temp table first, then the four are joined on (point, index).
CREATE OR ALTER PROCEDURE etl.usp_load_weather
    @windows_per_batch INT = 12
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
        WHERE source = 'weather' AND loaded_at IS NULL
        ORDER BY window_start;
        IF @@ROWCOUNT = 0 BREAK;

        DROP TABLE IF EXISTS #points;
        SELECT b.window_start, CAST(p.[key] AS TINYINT) + 1 AS point_id, p.value AS point_json
        INTO #points
        FROM @batch AS b
        JOIN stg.v_api_raw AS r ON r.source = 'weather' AND r.window_start = b.window_start
        CROSS APPLY OPENJSON(r.payload) AS p;

        DROP TABLE IF EXISTS #time, #wind, #solar, #temp;
        CREATE TABLE #time  (window_start DATE, point_id TINYINT, i INT, v NVARCHAR(20), PRIMARY KEY (window_start, point_id, i));
        CREATE TABLE #wind  (window_start DATE, point_id TINYINT, i INT, v NVARCHAR(20), PRIMARY KEY (window_start, point_id, i));
        CREATE TABLE #solar (window_start DATE, point_id TINYINT, i INT, v NVARCHAR(20), PRIMARY KEY (window_start, point_id, i));
        CREATE TABLE #temp  (window_start DATE, point_id TINYINT, i INT, v NVARCHAR(20), PRIMARY KEY (window_start, point_id, i));

        INSERT #time  SELECT p.window_start, p.point_id, CAST(a.[key] AS INT), a.value FROM #points AS p CROSS APPLY OPENJSON(p.point_json, '$.hourly.time') AS a;
        INSERT #wind  SELECT p.window_start, p.point_id, CAST(a.[key] AS INT), a.value FROM #points AS p CROSS APPLY OPENJSON(p.point_json, '$.hourly.wind_speed_100m') AS a;
        INSERT #solar SELECT p.window_start, p.point_id, CAST(a.[key] AS INT), a.value FROM #points AS p CROSS APPLY OPENJSON(p.point_json, '$.hourly.shortwave_radiation') AS a;
        INSERT #temp  SELECT p.window_start, p.point_id, CAST(a.[key] AS INT), a.value FROM #points AS p CROSS APPLY OPENJSON(p.point_json, '$.hourly.temperature_2m') AS a;

        BEGIN TRANSACTION;
            DELETE f
            FROM fact.weather_hourly AS f
            JOIN @batch AS b ON f.hour_start_utc >= CAST(b.window_start AS DATETIME2(0))
                            AND f.hour_start_utc <  CAST(b.window_end AS DATETIME2(0));

            -- Hours the archive hasn't reached yet come back as nulls; they're left out and
            -- filled in when the window is downloaded again.
            INSERT fact.weather_hourly (hour_start_utc, point_id, wind_speed_100m, solar_radiation, temperature_c)
            SELECT CAST(LEFT(t.v, 16) + ':00' AS DATETIME2(0)), t.point_id,
                   TRY_CAST(w.v AS DECIMAL(4, 1)), TRY_CAST(ROUND(TRY_CAST(s.v AS FLOAT), 0) AS SMALLINT),
                   TRY_CAST(te.v AS DECIMAL(4, 1))
            FROM #time AS t
            JOIN #wind  AS w  ON w.window_start  = t.window_start AND w.point_id  = t.point_id AND w.i  = t.i
            JOIN #solar AS s  ON s.window_start  = t.window_start AND s.point_id  = t.point_id AND s.i  = t.i
            JOIN #temp  AS te ON te.window_start = t.window_start AND te.point_id = t.point_id AND te.i = t.i
            WHERE w.v IS NOT NULL OR s.v IS NOT NULL OR te.v IS NOT NULL;
            SET @rows += @@ROWCOUNT;

            UPDATE r SET loaded_at = SYSUTCDATETIME()
            FROM stg.api_raw AS r JOIN @batch AS b ON r.source = 'weather' AND r.window_start = b.window_start;
        COMMIT;
    END;

    SELECT 'weather' AS source, @rows AS rows_loaded;
END;
GO
