-- Data-quality checks, one row per check: how many rows fail it. Blocking checks stop the
-- export (the site keeps its last good data); the others are reported on the site as caveats,
-- because they describe gaps in the source data rather than a broken load.
CREATE OR REPLACE VIEW etl.v_data_quality_checks AS
SELECT 'Downloads waiting to be loaded' AS check_name, true AS is_blocking,
       (SELECT COUNT(*) FROM stg.api_raw WHERE loaded_at IS NULL) AS failures
UNION ALL
SELECT 'National half-hours loaded', true,
       CASE WHEN EXISTS (SELECT 1 FROM fact.national_intensity) THEN 0 ELSE 1 END
UNION ALL
SELECT 'Intensity outside 0-1,000 g/kWh', true,
       (SELECT COUNT(*) FROM fact.national_intensity WHERE actual < 0 OR actual > 1000 OR forecast < 0 OR forecast > 1000)
     + (SELECT COUNT(*) FROM fact.regional_intensity WHERE intensity < 0 OR intensity > 1000)
UNION ALL
SELECT 'National half-hours missing', false,
       (SELECT date_diff('minute', MIN(period_start_utc), MAX(period_start_utc)) // 30 + 1 - COUNT(*)
        FROM fact.national_intensity)
UNION ALL
SELECT 'National half-hours over a week old with no actual', false,
       (SELECT COUNT(*) FROM fact.national_intensity
        WHERE actual IS NULL AND period_start_utc < timezone('UTC', now()) - INTERVAL 7 DAY)
UNION ALL
SELECT 'National mixes not adding up to 100% (+/- 2)', false,
       (SELECT COUNT(*) FROM (SELECT period_start_utc FROM fact.national_mix
                              GROUP BY period_start_utc HAVING SUM(share_pct) NOT BETWEEN 98 AND 102) AS bad)
UNION ALL
SELECT 'Regional half-hours without all 18 regions', false,
       (SELECT COUNT(*) FROM (SELECT period_start_utc FROM fact.regional_intensity
                              GROUP BY period_start_utc HAVING COUNT(*) <> 18) AS bad)
UNION ALL
SELECT 'Weather hours without all 15 points', false,
       (SELECT COUNT(*) FROM (SELECT hour_start_utc FROM fact.weather_hourly
                              GROUP BY hour_start_utc HAVING COUNT(*) <> 15) AS bad)
UNION ALL
SELECT 'Price half-hours without all 14 regions', false,
       (SELECT COUNT(*) FROM (SELECT period_start_utc FROM fact.price
                              GROUP BY period_start_utc HAVING COUNT(*) <> 14) AS bad)
UNION ALL
SELECT 'Prices outside -100p to 500p per kWh', true,
       (SELECT COUNT(*) FROM fact.price WHERE price_p_kwh < -100 OR price_p_kwh > 500)
UNION ALL
SELECT 'GB generation history loaded', true,
       CASE WHEN EXISTS (SELECT 1 FROM fact.gb_generation) THEN 0 ELSE 1 END
UNION ALL
SELECT 'GB generation half-hours missing', false,
       (SELECT date_diff('minute', MIN(period_start_utc), MAX(period_start_utc)) // 30 + 1 - COUNT(DISTINCT period_start_utc)
        FROM fact.gb_generation)
UNION ALL
SELECT 'Negative GB generation (other than storage)', false,
       (SELECT COUNT(*) FROM fact.gb_generation AS g JOIN dim.fuel AS f ON f.fuel_id = g.fuel_id
        WHERE g.mw < 0 AND f.fuel_key NOT IN ('storage', 'imports'))
UNION ALL
SELECT 'Technologies without a capacity actual, outlook and target', true,
       (SELECT 4 - COUNT(*) FROM (SELECT technology FROM fact.capacity
                                  GROUP BY technology HAVING COUNT(DISTINCT basis) = 3) AS complete);
