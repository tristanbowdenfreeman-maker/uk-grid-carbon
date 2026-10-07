-- Loads fact.capacity from the capacity window, replacing it in full. The payload holds every
-- Future Energy Scenarios edition's ES1 table and NESO's Clean Power 2030 portfolio:
-- {"fes": {"2020": [rows], ...}, "adequacy": [rows]}. ES1 has one column per year ("2019",
-- "2020", ...), read here with OPENJSON's key/value form. Older editions spell technologies and
-- the scenario column differently ("Offshore wind", "Solar PV", "Pathway"), so they're normalised.
CREATE OR ALTER PROCEDURE etl.usp_load_capacity
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rows INT = 0;

    IF NOT EXISTS (SELECT 1 FROM stg.api_raw WHERE source = 'capacity' AND loaded_at IS NULL)
    BEGIN
        SELECT 'capacity' AS source, 0 AS rows_loaded;
        RETURN;
    END;

    DROP TABLE IF EXISTS #fes;
    SELECT CAST(ed.[key] AS SMALLINT) AS edition,
           COALESCE(NULLIF(JSON_VALUE(rec.[value], '$.Scenario'), ''), JSON_VALUE(rec.[value], '$.Pathway')) AS scenario,
           CASE LOWER(LTRIM(RTRIM(JSON_VALUE(rec.[value], '$.Type'))))
                WHEN 'offshore wind' THEN 'Offshore wind'
                WHEN 'onshore wind'  THEN 'Onshore wind'
                WHEN 'solar'         THEN 'Solar'
                WHEN 'solar pv'      THEN 'Solar'
                WHEN 'battery'       THEN 'Batteries' END AS technology,
           CAST(kv.[key] AS SMALLINT) AS [year],
           TRY_CAST(REPLACE(CAST(kv.[value] AS VARCHAR(30)), ',', '') AS DECIMAL(12, 2)) AS mw
    INTO #fes
    FROM stg.v_api_raw AS r
    CROSS APPLY OPENJSON(r.payload, '$.fes') AS ed
    CROSS APPLY OPENJSON(ed.[value]) AS rec
    CROSS APPLY OPENJSON(rec.[value]) AS kv
    WHERE r.source = 'capacity'
      AND JSON_VALUE(rec.[value], '$.Variable') = 'Capacity (MW)'
      AND kv.[key] LIKE '[12][0-9][0-9][0-9]';
    DELETE #fes WHERE technology IS NULL OR mw IS NULL OR scenario IS NULL;

    DECLARE @latest SMALLINT = (SELECT MAX(edition) FROM #fes);

    BEGIN TRANSACTION;
        DELETE fact.capacity;

        -- Each edition's first year is history, the same in every scenario: sum the connection
        -- types (transmission, distribution, micro) within a scenario, then take any scenario.
        INSERT fact.capacity (technology, [year], basis, source_name, capacity_mw)
        SELECT technology, [year], 'actual', CONCAT('NESO FES ', edition), MAX(total)
        FROM (SELECT edition, scenario, technology, [year], SUM(mw) AS total
              FROM #fes
              WHERE [year] = edition - 1
              GROUP BY edition, scenario, technology, [year]) AS by_scenario
        WHERE total > 0
        GROUP BY technology, [year], edition;
        SET @rows += @@ROWCOUNT;

        -- The newest edition's ten-year outlook ("Ten Year Forecast" in 2025, "Outlook" since).
        INSERT fact.capacity (technology, [year], basis, source_name, capacity_mw)
        SELECT technology, 2030, 'outlook', CONCAT('NESO FES ', @latest, ' ', MIN(scenario)), SUM(mw)
        FROM #fes
        WHERE edition = @latest AND [year] = 2030 AND scenario LIKE 'Ten Year%'
        GROUP BY technology;
        SET @rows += @@ROWCOUNT;

        INSERT fact.capacity (technology, [year], basis, source_name, capacity_mw)
        SELECT a.technology, 2030, 'target', 'NESO Clean Power 2030 portfolio', SUM(a.mw)
        FROM stg.v_api_raw AS r
        CROSS APPLY OPENJSON(r.payload, '$.adequacy') WITH (
            future_year  VARCHAR(10)   '$."Future Year"',
            tech         VARCHAR(60)   '$.Technology',
            mw           DECIMAL(12, 2) '$."Installed Capacity (MW)"'
        ) AS j
        CROSS APPLY (SELECT CASE j.tech WHEN 'Offshore wind' THEN 'Offshore wind' WHEN 'Onshore wind' THEN 'Onshore wind'
                                        WHEN 'Solar' THEN 'Solar' WHEN 'Batteries' THEN 'Batteries' END AS technology,
                            j.mw) AS a
        WHERE r.source = 'capacity' AND j.future_year = '2030/31' AND a.technology IS NOT NULL
        GROUP BY a.technology;
        SET @rows += @@ROWCOUNT;

        UPDATE stg.api_raw SET loaded_at = SYSUTCDATETIME() WHERE source = 'capacity';
    COMMIT;

    SELECT 'capacity' AS source, @rows AS rows_loaded;
END;
GO
