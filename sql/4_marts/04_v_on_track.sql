-- The answer to "are we on track?" in one row.
--   recent_pace   the trend in the clean share over the last seven full years, in percentage
--                 points a year (least-squares slope, so one odd year doesn't swing it)
--   needed_pace   what it takes to get from the last 12 months to 95% in 2030
--   projected_2030  where the recent trend leads
-- Years are measured from the middle of the last 12 months to the middle of 2030.
CREATE OR ALTER VIEW mart.v_on_track
AS
WITH latest AS (
    SELECT MAX(period_start_utc) AS last_period,
           YEAR(MAX(period_start_utc)) - 1 AS last_full_year
    FROM fact.gb_generation
),
years AS (
    SELECT CAST(a.period AS INT) AS [year], CAST(a.clean_pct AS FLOAT) AS clean_pct
    FROM mart.v_gb_annual AS a
    CROSS JOIN latest AS l
    WHERE a.period NOT IN ('L12M', 'P12M') AND CAST(a.period AS INT) BETWEEN l.last_full_year - 6 AND l.last_full_year
),
fit AS (
    SELECT (COUNT(*) * SUM([year] * clean_pct) - SUM([year]) * SUM(clean_pct))
           / NULLIF(COUNT(*) * SUM(CAST([year] AS FLOAT) * [year]) - SUM(CAST([year] AS FLOAT)) * SUM([year]), 0) AS slope,
           MIN([year]) AS from_year, MAX([year]) AS to_year
    FROM years
),
now AS (
    SELECT (SELECT clean_pct FROM mart.v_gb_annual WHERE period = 'L12M') AS l12m,
           (SELECT clean_pct FROM mart.v_gb_annual WHERE period = 'P12M') AS p12m,
           (SELECT gas_pct FROM mart.v_gb_annual WHERE period = 'L12M') AS gas_l12m,
           (SELECT clean_pct FROM mart.v_gb_annual WHERE period = '2009') AS clean_2009,
           DATEDIFF(DAY, DATEADD(DAY, -183, l.last_period), '2030-07-01') / 365.25 AS years_left,
           l.last_period
    FROM latest AS l
)
SELECT n.last_period                                               AS last_period_utc,
       CAST(95 AS DECIMAL(4, 1))                                    AS target_pct,
       n.l12m                                                       AS clean_l12m,
       n.p12m                                                       AS clean_p12m,
       n.gas_l12m,
       n.clean_2009,
       f.from_year                                                  AS trend_from_year,
       f.to_year                                                    AS trend_to_year,
       CAST(f.slope AS DECIMAL(4, 2))                               AS recent_pace,
       CAST((95 - n.l12m) / n.years_left AS DECIMAL(4, 2))          AS needed_pace,
       CAST((95 - n.l12m) / n.years_left / NULLIF(f.slope, 0) AS DECIMAL(4, 1)) AS pace_ratio,
       CAST(n.years_left AS DECIMAL(4, 2))                          AS years_left,
       CAST(n.l12m + f.slope * n.years_left AS DECIMAL(4, 1))       AS projected_2030
FROM now AS n
CROSS JOIN fit AS f;
GO
