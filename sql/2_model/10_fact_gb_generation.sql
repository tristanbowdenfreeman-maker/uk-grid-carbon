-- Great Britain's generation by fuel, in megawatts, for every half-hour since 2009 (NESO's
-- historic generation mix). Wind is NESO's metered and embedded wind added together. About three
-- million rows, stored as a clustered columnstore because the marts scan whole years.
IF OBJECT_ID(N'fact.gb_generation') IS NULL
BEGIN
    CREATE TABLE fact.gb_generation (
        period_start_utc  DATETIME2(0)  NOT NULL,
        fuel_id           TINYINT       NOT NULL,
        date_key          INT           NOT NULL,
        half_hour         TINYINT       NOT NULL,
        mw                DECIMAL(8, 1) NOT NULL
    );
    CREATE CLUSTERED COLUMNSTORE INDEX CCI_fact_gb_generation ON fact.gb_generation;
END;
GO
