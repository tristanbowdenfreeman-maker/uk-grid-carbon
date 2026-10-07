-- Each region's generation mix for each half-hour: 18 regions x 9 fuels x every half-hour since
-- May 2018, about 25 million rows. A clustered columnstore index stores it compressed by column,
-- which is the right shape for the marts: they scan whole years and aggregate.
IF OBJECT_ID(N'fact.regional_mix') IS NULL
BEGIN
    CREATE TABLE fact.regional_mix (
        period_start_utc  DATETIME2(0)  NOT NULL,
        region_id         TINYINT       NOT NULL,
        fuel_id           TINYINT       NOT NULL,
        date_key          INT           NOT NULL,
        half_hour         TINYINT       NOT NULL,
        share_pct         DECIMAL(4, 1) NOT NULL
    );
    CREATE CLUSTERED COLUMNSTORE INDEX CCI_fact_regional_mix ON fact.regional_mix;
END;
GO
