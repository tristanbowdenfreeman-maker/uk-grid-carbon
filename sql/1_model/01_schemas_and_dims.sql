-- One schema per layer: the download log, the star schema, the load checks and the views the
-- website reads. The warehouse is a single DuckDB file (warehouse/grid.duckdb).
CREATE SCHEMA IF NOT EXISTS stg;   -- what has been downloaded and loaded
CREATE SCHEMA IF NOT EXISTS dim;   -- dimensions
CREATE SCHEMA IF NOT EXISTS fact;  -- facts
CREATE SCHEMA IF NOT EXISTS etl;   -- data-quality checks
CREATE SCHEMA IF NOT EXISTS mart;  -- one view per dataset on the site

-- UK local time for a UTC timestamp, as the facts store it: the local timestamp, its date_key
-- (yyyymmdd) and its half-hour of the day (0 = 00:00-00:30, 47 = 23:30-24:00). Clocks change in
-- spring and autumn, so a local day has 46 or 50 half-hours twice a year.
CREATE OR REPLACE MACRO etl.uk_time(utc) AS timezone('Europe/London', timezone('UTC', utc));
CREATE OR REPLACE MACRO etl.uk_date_key(utc) AS
    CAST(year(etl.uk_time(utc)) * 10000 + month(etl.uk_time(utc)) * 100 + day(etl.uk_time(utc)) AS INTEGER);
CREATE OR REPLACE MACRO etl.uk_half_hour(utc) AS
    CAST(hour(etl.uk_time(utc)) * 2 + minute(etl.uk_time(utc)) // 30 AS TINYINT);

-- Every download, one row per source and date window. The payloads themselves are not kept in
-- the warehouse (the daily job only needs to know what it has already fetched). loaded_at says
-- when the facts were last loaded from the window: a re-download clears it, so the loaders pick
-- the window up again.
CREATE TABLE IF NOT EXISTS stg.api_raw (
    source           VARCHAR   NOT NULL,
    window_start     DATE      NOT NULL,
    window_end       DATE      NOT NULL,
    compressed_bytes BIGINT    NOT NULL,
    fetched_at       TIMESTAMP NOT NULL,
    loaded_at        TIMESTAMP,
    PRIMARY KEY (source, window_start)
);

-- One row per UK calendar day. Facts join on date_key (yyyymmdd of the UK local date). Every
-- day from 2009 (where NESO's generation history starts) to the end of 2030, the target year.
CREATE TABLE IF NOT EXISTS dim.date (
    date_key     INTEGER  NOT NULL PRIMARY KEY,
    date         DATE     NOT NULL,
    year         SMALLINT NOT NULL,
    month        TINYINT  NOT NULL,
    month_name   VARCHAR  NOT NULL,
    day_of_week  TINYINT  NOT NULL,  -- 1 = Monday
    day_name     VARCHAR  NOT NULL,
    is_weekend   BOOLEAN  NOT NULL,
    season       VARCHAR  NOT NULL   -- meteorological: winter is December to February
);
INSERT INTO dim.date
SELECT CAST(strftime(d, '%Y%m%d') AS INTEGER), d, year(d), month(d), strftime(d, '%b'),
       isodow(d), strftime(d, '%a'), isodow(d) >= 6,
       CASE WHEN month(d) IN (12, 1, 2) THEN 'Winter'
            WHEN month(d) IN (3, 4, 5)  THEN 'Spring'
            WHEN month(d) IN (6, 7, 8)  THEN 'Summer'
            ELSE 'Autumn' END
FROM (SELECT CAST(unnest(generate_series(DATE '2009-01-01', DATE '2030-12-31', INTERVAL 1 DAY)) AS DATE) AS d) AS days
WHERE NOT EXISTS (SELECT 1 FROM dim.date AS existing WHERE existing.date = days.d);

-- The Carbon Intensity API's regions: the 14 distribution network operator (DNO) areas, then
-- England, Scotland, Wales and Great Britain as a whole. tariff_region is the letter Octopus Energy
-- prices each DNO region by (its GSP group).
CREATE TABLE IF NOT EXISTS dim.region (
    region_id     TINYINT NOT NULL PRIMARY KEY,
    region_name   VARCHAR NOT NULL,
    dno_operator  VARCHAR NOT NULL,
    country       VARCHAR NOT NULL,
    is_aggregate  BOOLEAN NOT NULL,
    tariff_region VARCHAR
);
DELETE FROM dim.region;
INSERT INTO dim.region VALUES
    (1,  'North Scotland',           'Scottish Hydro Electric Power Distribution', 'Scotland', false, 'P'),
    (2,  'South Scotland',           'SP Distribution',                            'Scotland', false, 'N'),
    (3,  'North West England',       'Electricity North West',                     'England',  false, 'G'),
    (4,  'North East England',       'NPG North East',                             'England',  false, 'F'),
    (5,  'Yorkshire',                'NPG Yorkshire',                              'England',  false, 'M'),
    (6,  'North Wales & Merseyside', 'SP Manweb',                                  'Wales',    false, 'D'),
    (7,  'South Wales',              'WPD South Wales',                            'Wales',    false, 'K'),
    (8,  'West Midlands',            'WPD West Midlands',                          'England',  false, 'E'),
    (9,  'East Midlands',            'WPD East Midlands',                          'England',  false, 'B'),
    (10, 'East England',             'UKPN East',                                  'England',  false, 'A'),
    (11, 'South West England',       'WPD South West',                             'England',  false, 'L'),
    (12, 'South England',            'SSE South',                                  'England',  false, 'H'),
    (13, 'London',                   'UKPN London',                                'England',  false, 'C'),
    (14, 'South East England',       'UKPN South East',                            'England',  false, 'J'),
    (15, 'England',                  'England',                                    'England',  true,  NULL),
    (16, 'Scotland',                 'Scotland',                                   'Scotland', true,  NULL),
    (17, 'Wales',                    'Wales',                                      'Wales',    true,  NULL),
    (18, 'Great Britain',            'GB',                                         'GB',       true,  NULL);

-- Where the hourly weather comes from: a central town in each DNO region, plus Dogger Bank in the
-- North Sea for offshore wind. Kept in step with WEATHER_POINTS in src/grid_carbon/sources.py:
-- the weather payload lists the points in this order.
CREATE TABLE IF NOT EXISTS dim.weather_point (
    point_id    TINYINT      NOT NULL PRIMARY KEY,
    point_name  VARCHAR      NOT NULL,
    latitude    DECIMAL(5,2) NOT NULL,
    longitude   DECIMAL(5,2) NOT NULL,
    region_id   TINYINT,
    is_offshore BOOLEAN      NOT NULL
);
DELETE FROM dim.weather_point;
INSERT INTO dim.weather_point VALUES
    (1,  'Inverness',        57.48, -4.22, 1,    false),
    (2,  'Southern Uplands', 55.60, -3.60, 2,    false),
    (3,  'Manchester',       53.48, -2.24, 3,    false),
    (4,  'Newcastle',        54.97, -1.61, 4,    false),
    (5,  'Leeds',            53.80, -1.55, 5,    false),
    (6,  'Denbighshire',     53.20, -3.30, 6,    false),
    (7,  'Merthyr Tydfil',   51.70, -3.50, 7,    false),
    (8,  'Birmingham',       52.48, -1.90, 8,    false),
    (9,  'Nottingham',       52.95, -1.15, 9,    false),
    (10, 'Norfolk',          52.40,  0.90, 10,   false),
    (11, 'Exeter',           50.72, -3.53, 11,   false),
    (12, 'Hampshire',        51.10, -1.30, 12,   false),
    (13, 'London',           51.51, -0.13, 13,   false),
    (14, 'Kent',             51.20,  0.70, 14,   false),
    (15, 'Dogger Bank',      54.75,  1.90, NULL, true);

-- The fuels in the generation mix. Clean (low carbon) = renewables plus nuclear, the Clean Power
-- 2030 definition. Imports, "other" and storage count as neither: imports aren't generated in
-- Britain, and the sources don't say what the other two are made from. Storage only appears in
-- NESO's history (pumped hydro and batteries discharging).
CREATE TABLE IF NOT EXISTS dim.fuel (
    fuel_id        TINYINT NOT NULL PRIMARY KEY,
    fuel_key       VARCHAR NOT NULL UNIQUE,
    fuel_name      VARCHAR NOT NULL,
    fuel_group     VARCHAR NOT NULL,  -- Fossil, Renewable, Nuclear, Other
    is_low_carbon  BOOLEAN NOT NULL,
    is_renewable   BOOLEAN NOT NULL,
    sort_order     TINYINT NOT NULL
);
DELETE FROM dim.fuel;
INSERT INTO dim.fuel VALUES
    (1,  'wind',    'Wind',    'Renewable', true,  true,  1),
    (2,  'solar',   'Solar',   'Renewable', true,  true,  2),
    (3,  'hydro',   'Hydro',   'Renewable', true,  true,  3),
    (4,  'biomass', 'Biomass', 'Renewable', true,  true,  4),
    (5,  'nuclear', 'Nuclear', 'Nuclear',   true,  false, 5),
    (6,  'imports', 'Imports', 'Other',     false, false, 6),
    (7,  'other',   'Other',   'Other',     false, false, 7),
    (8,  'gas',     'Gas',     'Fossil',    false, false, 8),
    (9,  'coal',    'Coal',    'Fossil',    false, false, 9),
    (10, 'storage', 'Storage', 'Other',     false, false, 10);
