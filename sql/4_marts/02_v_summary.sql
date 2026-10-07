-- How much data the dashboard stands on, for the "How it's built" strip: rows in each fact
-- table, the downloads behind them and the date range of the generation history.
CREATE OR ALTER VIEW mart.v_summary
AS
SELECT (SELECT MIN(period_start_utc) FROM fact.gb_generation)        AS first_period_utc,
       (SELECT MAX(period_start_utc) FROM fact.gb_generation)        AS last_period_utc,
       (SELECT COUNT_BIG(*) FROM fact.gb_generation)                 AS gb_generation_rows,
       (SELECT COUNT_BIG(*) FROM fact.national_intensity)            AS national_periods,
       (SELECT COUNT_BIG(*) FROM fact.national_mix)                  AS national_mix_rows,
       (SELECT COUNT_BIG(*) FROM fact.regional_intensity)            AS regional_periods,
       (SELECT COUNT_BIG(*) FROM fact.regional_mix)                  AS regional_mix_rows,
       (SELECT COUNT_BIG(*) FROM fact.weather_hourly)                AS weather_rows,
       (SELECT COUNT_BIG(*) FROM fact.price)                         AS price_rows,
       (SELECT COUNT_BIG(*) FROM fact.capacity)                      AS capacity_rows,
       (SELECT COUNT(DISTINCT source) FROM stg.api_raw)              AS sources,
       (SELECT COUNT(*) FROM stg.api_raw)                            AS api_downloads,
       (SELECT CAST(SUM(DATALENGTH(payload_gz)) / 1048576.0 AS DECIMAL(9, 1)) FROM stg.api_raw) AS raw_mb_compressed;
GO
