-- Each region in each period (calendar year or last 12 months): average estimated intensity,
-- the share of half-hours that were 'very low' or 'low', the average share of each fuel, and
-- clean_pct: the clean share of electricity generated in the region (imports left out, the same
-- measure as the national headline).
-- The mix comes from the 25-million-row columnstore table, summed by day before the period join.
CREATE OR ALTER VIEW mart.v_region_summary
AS
WITH intensity AS (
    SELECT p.period, ri.region_id,
           COUNT(*) AS periods,
           AVG(CAST(ri.intensity AS DECIMAL(9, 2))) AS avg_intensity,
           AVG(CASE WHEN ri.intensity_index IN ('very low', 'low') THEN 1.0 ELSE 0.0 END) AS low_share
    FROM mart.v_region_period AS p
    JOIN fact.regional_intensity AS ri ON ri.date_key BETWEEN p.from_key AND p.to_key
    GROUP BY p.period, ri.region_id
),
daily_mix AS (
    -- Daily totals first (about half a million rows), so the period join stays small.
    SELECT region_id, fuel_id, date_key, SUM(share_pct) AS share_sum, COUNT(*) AS periods
    FROM fact.regional_mix
    GROUP BY region_id, fuel_id, date_key
),
mix AS (
    SELECT p.period, dm.region_id,
           SUM(CASE WHEN f.fuel_key = 'wind'    THEN dm.share_sum END) / SUM(CASE WHEN f.fuel_key = 'wind'    THEN dm.periods END) AS wind_pct,
           SUM(CASE WHEN f.fuel_key = 'solar'   THEN dm.share_sum END) / SUM(CASE WHEN f.fuel_key = 'solar'   THEN dm.periods END) AS solar_pct,
           SUM(CASE WHEN f.fuel_key = 'hydro'   THEN dm.share_sum END) / SUM(CASE WHEN f.fuel_key = 'hydro'   THEN dm.periods END) AS hydro_pct,
           SUM(CASE WHEN f.fuel_key = 'biomass' THEN dm.share_sum END) / SUM(CASE WHEN f.fuel_key = 'biomass' THEN dm.periods END) AS biomass_pct,
           SUM(CASE WHEN f.fuel_key = 'nuclear' THEN dm.share_sum END) / SUM(CASE WHEN f.fuel_key = 'nuclear' THEN dm.periods END) AS nuclear_pct,
           SUM(CASE WHEN f.fuel_key = 'imports' THEN dm.share_sum END) / SUM(CASE WHEN f.fuel_key = 'imports' THEN dm.periods END) AS imports_pct,
           SUM(CASE WHEN f.fuel_key = 'other'   THEN dm.share_sum END) / SUM(CASE WHEN f.fuel_key = 'other'   THEN dm.periods END) AS other_pct,
           SUM(CASE WHEN f.fuel_key = 'gas'     THEN dm.share_sum END) / SUM(CASE WHEN f.fuel_key = 'gas'     THEN dm.periods END) AS gas_pct,
           SUM(CASE WHEN f.fuel_key = 'coal'    THEN dm.share_sum END) / SUM(CASE WHEN f.fuel_key = 'coal'    THEN dm.periods END) AS coal_pct
    FROM mart.v_region_period AS p
    JOIN daily_mix AS dm ON dm.date_key BETWEEN p.from_key AND p.to_key
    JOIN dim.fuel AS f ON f.fuel_id = dm.fuel_id
    GROUP BY p.period, dm.region_id
)
SELECT i.period,
       r.region_id,
       r.region_name,
       r.country,
       r.is_aggregate,
       i.periods,
       CAST(i.avg_intensity AS DECIMAL(6, 1)) AS avg_intensity,
       CAST(i.low_share AS DECIMAL(5, 4))     AS low_share,
       RANK() OVER (PARTITION BY i.period, r.is_aggregate ORDER BY i.avg_intensity) AS greenest_rank,
       CAST(m.wind_pct AS DECIMAL(4, 1))    AS wind_pct,
       CAST(m.solar_pct AS DECIMAL(4, 1))   AS solar_pct,
       CAST(m.hydro_pct AS DECIMAL(4, 1))   AS hydro_pct,
       CAST(m.biomass_pct AS DECIMAL(4, 1)) AS biomass_pct,
       CAST(m.nuclear_pct AS DECIMAL(4, 1)) AS nuclear_pct,
       CAST(m.imports_pct AS DECIMAL(4, 1)) AS imports_pct,
       CAST(m.other_pct AS DECIMAL(4, 1))   AS other_pct,
       CAST(m.gas_pct AS DECIMAL(4, 1))     AS gas_pct,
       CAST(m.coal_pct AS DECIMAL(4, 1))    AS coal_pct,
       CAST(100 * (m.wind_pct + m.solar_pct + m.hydro_pct + m.biomass_pct + m.nuclear_pct)
            / NULLIF(100 - m.imports_pct, 0) AS DECIMAL(4, 1)) AS clean_pct
FROM intensity AS i
JOIN dim.region AS r ON r.region_id = i.region_id
LEFT JOIN mix AS m ON m.period = i.period AND m.region_id = i.region_id;
GO
