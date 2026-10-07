-- Where the hourly weather comes from: a central town in each DNO region, plus Dogger Bank in the
-- North Sea for offshore wind. Kept in step with WEATHER_POINTS in src/grid_carbon/sources.py:
-- the weather payload lists the points in this order.
IF OBJECT_ID(N'dim.weather_point') IS NULL
CREATE TABLE dim.weather_point (
    point_id    TINYINT       NOT NULL CONSTRAINT PK_dim_weather_point PRIMARY KEY,
    point_name  VARCHAR(30)   NOT NULL,
    latitude    DECIMAL(5, 2) NOT NULL,
    longitude   DECIMAL(5, 2) NOT NULL,
    region_id   TINYINT       NULL CONSTRAINT FK_weather_point_region REFERENCES dim.region (region_id),
    is_offshore BIT           NOT NULL
);
GO

MERGE dim.weather_point AS target
USING (VALUES
    (1,  'Inverness',     57.48, -4.22, 1,    0),
    (2,  'Southern Uplands', 55.60, -3.60, 2, 0),
    (3,  'Manchester',    53.48, -2.24, 3,    0),
    (4,  'Newcastle',     54.97, -1.61, 4,    0),
    (5,  'Leeds',         53.80, -1.55, 5,    0),
    (6,  'Denbighshire',  53.20, -3.30, 6,    0),
    (7,  'Merthyr Tydfil', 51.70, -3.50, 7,   0),
    (8,  'Birmingham',    52.48, -1.90, 8,    0),
    (9,  'Nottingham',    52.95, -1.15, 9,    0),
    (10, 'Norfolk',       52.40,  0.90, 10,   0),
    (11, 'Exeter',        50.72, -3.53, 11,   0),
    (12, 'Hampshire',     51.10, -1.30, 12,   0),
    (13, 'London',        51.51, -0.13, 13,   0),
    (14, 'Kent',          51.20,  0.70, 14,   0),
    (15, 'Dogger Bank',   54.75,  1.90, NULL, 1)
) AS source (point_id, point_name, latitude, longitude, region_id, is_offshore)
ON target.point_id = source.point_id
WHEN MATCHED THEN UPDATE SET point_name = source.point_name, latitude = source.latitude,
                             longitude = source.longitude, region_id = source.region_id,
                             is_offshore = source.is_offshore
WHEN NOT MATCHED THEN INSERT VALUES (source.point_id, source.point_name, source.latitude,
                                     source.longitude, source.region_id, source.is_offshore);
GO
