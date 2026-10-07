-- The periods the regional marts compare: each calendar year, plus the last 12 months as
-- 'L12M'. Not exported itself.
CREATE OR ALTER VIEW mart.v_region_period
AS
WITH latest AS (
    SELECT MAX(date_key) AS last_key FROM fact.regional_intensity
),
bounds AS (
    SELECT CAST(d.[year] AS VARCHAR(4)) AS period, MIN(d.date_key) AS from_key, MAX(d.date_key) AS to_key
    FROM dim.date AS d
    CROSS JOIN latest AS l
    WHERE d.date_key <= l.last_key AND d.date_key >= 20180511
    GROUP BY d.[year]
    UNION ALL
    SELECT 'L12M', CONVERT(INT, FORMAT(DATEADD(DAY, 1, DATEADD(YEAR, -1, CONVERT(DATE, CAST(l.last_key AS CHAR(8))))), 'yyyyMMdd')), l.last_key
    FROM latest AS l
)
SELECT period, from_key, to_key FROM bounds;
GO
