-- Octopus Agile's price for each region and half-hour, in pence per kWh including VAT. Set the day
-- before from wholesale prices, so it is the price signal a business could plan charging around.
IF OBJECT_ID(N'fact.price') IS NULL
CREATE TABLE fact.price (
    period_start_utc  DATETIME2(0) NOT NULL,
    region_id         TINYINT      NOT NULL CONSTRAINT FK_price_region REFERENCES dim.region (region_id),
    date_key          INT          NOT NULL,
    half_hour         TINYINT      NOT NULL,
    price_p_kwh       DECIMAL(7, 3) NOT NULL,
    product_code      VARCHAR(24)  NOT NULL,
    CONSTRAINT PK_fact_price PRIMARY KEY (period_start_utc, region_id)
);
GO
