-- Calm, breezy and windy half-hours in each region over the last 12 months, by the wind 100 m up
-- averaged across Britain: calm below 4 m/s (most turbines barely turn), windy from 10 m/s
-- (close to full output). How clean, how gas-heavy and how expensive each one is.
CREATE OR ALTER VIEW mart.v_region_wind
AS
WITH banded AS (
    SELECT region_id, clean_pct, gas_pct, price,
           CASE WHEN wind_speed_100m < 4 THEN 1 WHEN wind_speed_100m < 10 THEN 2 ELSE 3 END AS band_order
    FROM mart.v_region_half_hour
    WHERE wind_speed_100m IS NOT NULL
)
SELECT region_id,
       CAST(band_order AS TINYINT) AS band_order,
       CAST(CASE band_order WHEN 1 THEN 'Calm' WHEN 2 THEN 'Breezy' ELSE 'Windy' END AS VARCHAR(6)) AS band,
       COUNT(*)                                                        AS half_hours,
       CAST(COUNT(*) * 1.0 / SUM(COUNT(*)) OVER (PARTITION BY region_id) AS DECIMAL(5, 4)) AS share_of_time,
       CAST(AVG(clean_pct) AS DECIMAL(4, 1))                           AS clean_pct,
       CAST(AVG(gas_pct) AS DECIMAL(4, 1))                             AS gas_pct,
       CAST(AVG(price) AS DECIMAL(5, 2))                               AS price
FROM banded
GROUP BY region_id, band_order;
GO
