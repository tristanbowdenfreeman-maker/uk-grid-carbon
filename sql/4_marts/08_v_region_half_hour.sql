-- Every region's half-hours over the last 12 months with what page 2 needs: the clean and gas
-- share of the electricity generated in the region (imports left out, as nationally), its Agile
-- price, and the wind 100 m up averaged over all 15 weather points. England, Scotland, Wales and
-- Great Britain (the aggregate regions) get the average price of their regions. Not exported.
CREATE OR ALTER VIEW mart.v_region_half_hour
AS
WITH mix AS (
    SELECT rm.period_start_utc, rm.region_id, rm.date_key, rm.half_hour,
           SUM(CASE WHEN f.is_low_carbon = 1 THEN rm.share_pct ELSE 0 END) AS clean,
           SUM(CASE WHEN f.fuel_key = 'gas' THEN rm.share_pct ELSE 0 END) AS gas,
           SUM(CASE WHEN f.fuel_key = 'imports' THEN rm.share_pct ELSE 0 END) AS imports
    FROM fact.regional_mix AS rm
    JOIN dim.fuel AS f ON f.fuel_id = rm.fuel_id
    JOIN mart.v_region_period AS p ON p.period = 'L12M' AND rm.date_key BETWEEN p.from_key AND p.to_key
    GROUP BY rm.period_start_utc, rm.region_id, rm.date_key, rm.half_hour
),
area_price AS (
    SELECT pr.period_start_utc, ISNULL(r.country, 'GB') AS country, AVG(pr.price_p_kwh) AS price
    FROM fact.price AS pr
    JOIN dim.region AS r ON r.region_id = pr.region_id
    JOIN mart.v_region_period AS p ON p.period = 'L12M' AND pr.date_key BETWEEN p.from_key AND p.to_key
    GROUP BY GROUPING SETS ((pr.period_start_utc, r.country), (pr.period_start_utc))
),
wind AS (
    SELECT hour_start_utc, AVG(wind_speed_100m) AS wind_speed_100m
    FROM fact.weather_hourly
    GROUP BY hour_start_utc
)
SELECT m.period_start_utc,
       m.region_id,
       d.season,
       m.half_hour,
       100 * m.clean / NULLIF(100 - m.imports, 0) AS clean_pct,
       100 * m.gas / NULLIF(100 - m.imports, 0)   AS gas_pct,
       COALESCE(pr.price_p_kwh, ap.price)         AS price,
       w.wind_speed_100m
FROM mix AS m
JOIN dim.date AS d ON d.date_key = m.date_key
JOIN dim.region AS r ON r.region_id = m.region_id
LEFT JOIN fact.price AS pr ON r.is_aggregate = 0 AND pr.period_start_utc = m.period_start_utc AND pr.region_id = m.region_id
LEFT JOIN area_price AS ap ON r.is_aggregate = 1 AND ap.period_start_utc = m.period_start_utc AND ap.country = r.country
LEFT JOIN wind AS w ON w.hour_start_utc = DATEADD(MINUTE, -DATEPART(MINUTE, m.period_start_utc), m.period_start_utc)
WHERE m.imports < 100;
GO
