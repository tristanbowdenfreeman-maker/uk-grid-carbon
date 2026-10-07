-- Loads fact.gb_generation from the neso_mix windows not loaded yet (one calendar month each):
-- one row per half-hour and fuel. NESO sends numbers as text, hence TRY_CAST.
CREATE OR ALTER PROCEDURE etl.usp_load_gb_generation
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
        WHERE source = 'neso_mix' AND loaded_at IS NULL
        ORDER BY window_start;
        IF @@ROWCOUNT = 0 BREAK;

        DROP TABLE IF EXISTS #periods;
        SELECT TRY_CAST(j.[datetime] AS DATETIME2(0)) AS period_start_utc,
               TRY_CAST(j.gas AS DECIMAL(8, 1)) AS gas, TRY_CAST(j.coal AS DECIMAL(8, 1)) AS coal,
               TRY_CAST(j.nuclear AS DECIMAL(8, 1)) AS nuclear,
               TRY_CAST(j.wind AS DECIMAL(8, 1)) + ISNULL(TRY_CAST(j.wind_emb AS DECIMAL(8, 1)), 0) AS wind,
               TRY_CAST(j.hydro AS DECIMAL(8, 1)) AS hydro, TRY_CAST(j.imports AS DECIMAL(8, 1)) AS imports,
               TRY_CAST(j.biomass AS DECIMAL(8, 1)) AS biomass, TRY_CAST(j.other AS DECIMAL(8, 1)) AS other,
               TRY_CAST(j.solar AS DECIMAL(8, 1)) AS solar, TRY_CAST(j.storage AS DECIMAL(8, 1)) AS storage
        INTO #periods
        FROM @batch AS b
        JOIN stg.v_api_raw AS r ON r.source = 'neso_mix' AND r.window_start = b.window_start
        CROSS APPLY OPENJSON(r.payload, '$.result.records') WITH (
            [datetime] VARCHAR(25) '$.DATETIME', gas VARCHAR(12) '$.GAS', coal VARCHAR(12) '$.COAL',
            nuclear VARCHAR(12) '$.NUCLEAR', wind VARCHAR(12) '$.WIND', wind_emb VARCHAR(12) '$.WIND_EMB',
            hydro VARCHAR(12) '$.HYDRO', imports VARCHAR(12) '$.IMPORTS', biomass VARCHAR(12) '$.BIOMASS',
            other VARCHAR(12) '$.OTHER', solar VARCHAR(12) '$.SOLAR', storage VARCHAR(12) '$.STORAGE'
        ) AS j
        WHERE TRY_CAST(j.[datetime] AS DATETIME2(0)) >= CAST(b.window_start AS DATETIME2(0))
          AND TRY_CAST(j.[datetime] AS DATETIME2(0)) <  CAST(b.window_end AS DATETIME2(0));

        BEGIN TRANSACTION;
            DELETE f
            FROM fact.gb_generation AS f
            JOIN @batch AS b ON f.period_start_utc >= CAST(b.window_start AS DATETIME2(0))
                            AND f.period_start_utc <  CAST(b.window_end AS DATETIME2(0));

            INSERT fact.gb_generation (period_start_utc, fuel_id, date_key, half_hour, mw)
            SELECT p.period_start_utc, fu.fuel_id, uk.date_key, uk.half_hour, v.mw
            FROM #periods AS p
            CROSS APPLY etl.fn_uk_time(p.period_start_utc) AS uk
            CROSS APPLY (VALUES ('wind', p.wind), ('solar', p.solar), ('hydro', p.hydro), ('biomass', p.biomass),
                                ('nuclear', p.nuclear), ('imports', p.imports), ('other', p.other),
                                ('gas', p.gas), ('coal', p.coal), ('storage', p.storage)) AS v (fuel_key, mw)
            JOIN dim.fuel AS fu ON fu.fuel_key = v.fuel_key
            WHERE v.mw IS NOT NULL;
            SET @rows += @@ROWCOUNT;

            UPDATE r SET loaded_at = SYSUTCDATETIME()
            FROM stg.api_raw AS r JOIN @batch AS b ON r.source = 'neso_mix' AND r.window_start = b.window_start;
        COMMIT;
    END;

    SELECT 'neso_mix' AS source, @rows AS rows_loaded;
END;
GO
