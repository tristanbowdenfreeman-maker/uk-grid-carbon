-- Installed capacity for the build-out chart, in gigawatts: the history, the 2030 outlook and
-- the 2030 target for each technology.
CREATE OR ALTER VIEW mart.v_capacity
AS
SELECT technology,
       [year],
       basis,
       source_name,
       CAST(capacity_mw / 1000 AS DECIMAL(5, 1)) AS gw
FROM fact.capacity;
GO
