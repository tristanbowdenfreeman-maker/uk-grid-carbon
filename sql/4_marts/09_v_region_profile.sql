-- The average day in each region over the last 12 months, hour by hour (UK time): how clean and
-- how expensive electricity is. By season and for the whole year ('All year').
CREATE OR ALTER VIEW mart.v_region_profile
AS
SELECT region_id,
       CAST(COALESCE(season, 'All year') AS VARCHAR(8)) AS season,
       CAST(half_hour / 2 AS TINYINT)                   AS hour_uk,
       CAST(AVG(clean_pct) AS DECIMAL(4, 1))            AS clean_pct,
       CAST(AVG(gas_pct) AS DECIMAL(4, 1))              AS gas_pct,
       CAST(AVG(price) AS DECIMAL(5, 2))                AS price
FROM mart.v_region_half_hour
GROUP BY GROUPING SETS ((region_id, season, half_hour / 2), (region_id, half_hour / 2));
GO
