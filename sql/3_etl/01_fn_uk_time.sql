-- UK local time for a UTC timestamp, as the facts store it: the local timestamp, its date_key
-- (yyyymmdd) and its half-hour of the day (0 = 00:00-00:30, 47 = 23:30-24:00). Clocks change
-- in spring and autumn, so a local day has 46 or 50 half-hours twice a year.
CREATE OR ALTER FUNCTION etl.fn_uk_time (@utc DATETIME2(0))
RETURNS TABLE
AS
RETURN
SELECT uk.t AS period_start_uk,
       YEAR(uk.t) * 10000 + MONTH(uk.t) * 100 + DAY(uk.t) AS date_key,
       CAST(DATEPART(HOUR, uk.t) * 2 + DATEPART(MINUTE, uk.t) / 30 AS TINYINT) AS half_hour
FROM (SELECT CAST(@utc AT TIME ZONE 'UTC' AT TIME ZONE 'GMT Standard Time' AS DATETIME2(0)) AS t) AS uk;
GO
