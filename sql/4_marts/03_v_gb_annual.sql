-- Great Britain's generation mix for each calendar year since 2009, plus the last 12 months
-- ('L12M') and the 12 months before them ('P12M'). Shares are of electricity generated in
-- Britain, so imports are left out of the total: the measure Clean Power 2030 sets its 95%
-- target on. Clean = wind, solar, hydro, biomass and nuclear.
CREATE OR ALTER VIEW mart.v_gb_annual
AS
WITH latest AS (
    SELECT MAX(period_start_utc) AS last_period FROM fact.gb_generation
),
tagged AS (
    SELECT t.period, g.period_start_utc, f.fuel_key, f.is_low_carbon, g.mw
    FROM fact.gb_generation AS g
    JOIN dim.fuel AS f ON f.fuel_id = g.fuel_id
    CROSS JOIN latest AS l
    CROSS APPLY (VALUES
        (CAST(g.date_key / 10000 AS VARCHAR(4))),
        (CASE WHEN g.period_start_utc > DATEADD(YEAR, -1, l.last_period) THEN 'L12M' END),
        (CASE WHEN g.period_start_utc > DATEADD(YEAR, -2, l.last_period)
               AND g.period_start_utc <= DATEADD(YEAR, -1, l.last_period) THEN 'P12M' END)
    ) AS t (period)
    WHERE t.period IS NOT NULL AND f.fuel_key <> 'imports'
),
totals AS (
    SELECT period,
           COUNT(DISTINCT period_start_utc) AS half_hours,
           SUM(mw) AS generated,
           SUM(CASE WHEN fuel_key = 'wind' THEN mw END)                  AS wind,
           SUM(CASE WHEN fuel_key = 'solar' THEN mw END)                 AS solar,
           SUM(CASE WHEN fuel_key = 'nuclear' THEN mw END)               AS nuclear,
           SUM(CASE WHEN fuel_key IN ('hydro', 'biomass') THEN mw END)   AS other_clean,
           SUM(CASE WHEN fuel_key = 'gas' THEN mw END)                   AS gas,
           SUM(CASE WHEN fuel_key = 'coal' THEN mw END)                  AS coal,
           SUM(CASE WHEN fuel_key IN ('other', 'storage') THEN mw END)   AS other,
           SUM(CASE WHEN is_low_carbon = 1 THEN mw END)                  AS clean
    FROM tagged
    GROUP BY period
)
SELECT period,
       half_hours,
       CAST(generated / 2 / 1e6 AS DECIMAL(6, 1))        AS generated_twh,  -- MW over a half-hour = MWh / 2
       CAST(100 * wind / generated AS DECIMAL(4, 1))        AS wind_pct,
       CAST(100 * solar / generated AS DECIMAL(4, 1))       AS solar_pct,
       CAST(100 * nuclear / generated AS DECIMAL(4, 1))     AS nuclear_pct,
       CAST(100 * other_clean / generated AS DECIMAL(4, 1)) AS other_clean_pct,
       CAST(100 * gas / generated AS DECIMAL(4, 1))         AS gas_pct,
       CAST(100 * coal / generated AS DECIMAL(4, 1))        AS coal_pct,
       CAST(100 * other / generated AS DECIMAL(4, 1))       AS other_pct,
       CAST(100 * clean / generated AS DECIMAL(4, 1))       AS clean_pct
FROM totals;
GO
