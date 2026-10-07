-- The Carbon Intensity API's regions: the 14 distribution network operator (DNO) areas, then
-- England, Scotland, Wales and Great Britain as a whole. tariff_region is the letter Octopus Energy
-- prices each DNO region by (its GSP group).
IF OBJECT_ID(N'dim.region') IS NULL
CREATE TABLE dim.region (
    region_id     TINYINT      NOT NULL CONSTRAINT PK_dim_region PRIMARY KEY,
    region_name   VARCHAR(30)  NOT NULL,
    dno_operator  VARCHAR(50)  NOT NULL,
    country       VARCHAR(8)   NOT NULL,
    is_aggregate  BIT          NOT NULL,
    tariff_region CHAR(1)      NULL
);
GO

MERGE dim.region AS target
USING (VALUES
    (1,  'North Scotland',           'Scottish Hydro Electric Power Distribution', 'Scotland', 0, 'P'),
    (2,  'South Scotland',           'SP Distribution',                            'Scotland', 0, 'N'),
    (3,  'North West England',       'Electricity North West',                     'England',  0, 'G'),
    (4,  'North East England',       'NPG North East',                             'England',  0, 'F'),
    (5,  'Yorkshire',                'NPG Yorkshire',                              'England',  0, 'M'),
    (6,  'North Wales & Merseyside', 'SP Manweb',                                  'Wales',    0, 'D'),
    (7,  'South Wales',              'WPD South Wales',                            'Wales',    0, 'K'),
    (8,  'West Midlands',            'WPD West Midlands',                          'England',  0, 'E'),
    (9,  'East Midlands',            'WPD East Midlands',                          'England',  0, 'B'),
    (10, 'East England',             'UKPN East',                                  'England',  0, 'A'),
    (11, 'South West England',       'WPD South West',                             'England',  0, 'L'),
    (12, 'South England',            'SSE South',                                  'England',  0, 'H'),
    (13, 'London',                   'UKPN London',                                'England',  0, 'C'),
    (14, 'South East England',       'UKPN South East',                            'England',  0, 'J'),
    (15, 'England',                  'England',                                    'England',  1, NULL),
    (16, 'Scotland',                 'Scotland',                                   'Scotland', 1, NULL),
    (17, 'Wales',                    'Wales',                                      'Wales',    1, NULL),
    (18, 'Great Britain',            'GB',                                         'GB',       1, NULL)
) AS source (region_id, region_name, dno_operator, country, is_aggregate, tariff_region)
ON target.region_id = source.region_id
WHEN MATCHED THEN UPDATE SET region_name = source.region_name, dno_operator = source.dno_operator,
                             country = source.country, is_aggregate = source.is_aggregate,
                             tariff_region = source.tariff_region
WHEN NOT MATCHED THEN INSERT VALUES (source.region_id, source.region_name, source.dno_operator,
                                     source.country, source.is_aggregate, source.tariff_region);
GO
