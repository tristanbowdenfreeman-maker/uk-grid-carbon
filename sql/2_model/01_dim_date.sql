-- One row per UK calendar day. Facts join on date_key (yyyymmdd of the UK local date).
IF OBJECT_ID(N'dim.date') IS NULL
CREATE TABLE dim.date (
    date_key     INT         NOT NULL CONSTRAINT PK_dim_date PRIMARY KEY,
    [date]       DATE        NOT NULL,
    [year]       SMALLINT    NOT NULL,
    [month]      TINYINT     NOT NULL,
    month_name   VARCHAR(3)  NOT NULL,
    day_of_week  TINYINT     NOT NULL,  -- 1 = Monday
    day_name     VARCHAR(3)  NOT NULL,
    is_weekend   BIT         NOT NULL,
    season       VARCHAR(6)  NOT NULL   -- meteorological: winter is December to February
);
GO

-- Every day from 2009 (where NESO's generation history starts) to the end of 2030, the target
-- year. Inserts only the days missing, so it extends an older table that started in 2018.
WITH days AS (
    SELECT DATEADD(DAY, n, CAST('2009-01-01' AS DATE)) AS d
    FROM (SELECT TOP (DATEDIFF(DAY, '2009-01-01', '2031-01-01'))
                 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n
          FROM sys.all_objects a CROSS JOIN sys.all_objects b) AS numbers
)
INSERT dim.date (date_key, [date], [year], [month], month_name, day_of_week, day_name, is_weekend, season)
SELECT CONVERT(INT, FORMAT(d, 'yyyyMMdd')),
       d,
       YEAR(d),
       MONTH(d),
       LEFT(DATENAME(MONTH, d), 3),
       DATEDIFF(DAY, '2018-01-01', d) % 7 + CASE WHEN DATEDIFF(DAY, '2018-01-01', d) % 7 < 0 THEN 8 ELSE 1 END,  -- 2018-01-01 was a Monday
       LEFT(DATENAME(WEEKDAY, d), 3),
       CASE WHEN (DATEDIFF(DAY, '2018-01-01', d) % 7 + 7) % 7 >= 5 THEN 1 ELSE 0 END,
       CASE WHEN MONTH(d) IN (12, 1, 2) THEN 'Winter'
            WHEN MONTH(d) IN (3, 4, 5)  THEN 'Spring'
            WHEN MONTH(d) IN (6, 7, 8)  THEN 'Summer'
            ELSE 'Autumn' END
FROM days
WHERE NOT EXISTS (SELECT 1 FROM dim.date AS existing WHERE existing.[date] = days.d);
GO
