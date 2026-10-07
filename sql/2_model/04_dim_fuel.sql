-- The fuels in the generation mix. Clean (low carbon) = renewables plus nuclear, the Clean Power
-- 2030 definition. Imports, "other" and storage count as neither: imports aren't generated in
-- Britain, and the sources don't say what the other two are made from. Storage only appears in
-- NESO's history (pumped hydro and batteries discharging).
IF OBJECT_ID(N'dim.fuel') IS NULL
CREATE TABLE dim.fuel (
    fuel_id        TINYINT     NOT NULL CONSTRAINT PK_dim_fuel PRIMARY KEY,
    fuel_key       VARCHAR(10) NOT NULL CONSTRAINT UQ_dim_fuel_key UNIQUE,
    fuel_name      VARCHAR(12) NOT NULL,
    fuel_group     VARCHAR(10) NOT NULL,  -- Fossil, Renewable, Nuclear, Other
    is_low_carbon  BIT         NOT NULL,
    is_renewable   BIT         NOT NULL,
    sort_order     TINYINT     NOT NULL
);
GO

MERGE dim.fuel AS target
USING (VALUES
    (1, 'wind',    'Wind',    'Renewable', 1, 1, 1),
    (2, 'solar',   'Solar',   'Renewable', 1, 1, 2),
    (3, 'hydro',   'Hydro',   'Renewable', 1, 1, 3),
    (4, 'biomass', 'Biomass', 'Renewable', 1, 1, 4),
    (5, 'nuclear', 'Nuclear', 'Nuclear',   1, 0, 5),
    (6, 'imports', 'Imports', 'Other',     0, 0, 6),
    (7, 'other',   'Other',   'Other',     0, 0, 7),
    (8, 'gas',     'Gas',     'Fossil',    0, 0, 8),
    (9, 'coal',    'Coal',    'Fossil',    0, 0, 9),
    (10, 'storage', 'Storage', 'Other',    0, 0, 10)
) AS source (fuel_id, fuel_key, fuel_name, fuel_group, is_low_carbon, is_renewable, sort_order)
ON target.fuel_id = source.fuel_id
WHEN MATCHED THEN UPDATE SET fuel_key = source.fuel_key, fuel_name = source.fuel_name,
                             fuel_group = source.fuel_group, is_low_carbon = source.is_low_carbon,
                             is_renewable = source.is_renewable, sort_order = source.sort_order
WHEN NOT MATCHED THEN INSERT VALUES (source.fuel_id, source.fuel_key, source.fuel_name, source.fuel_group,
                                     source.is_low_carbon, source.is_renewable, source.sort_order);
GO
