-- Great Britain's generation mix: the share of each fuel in each half-hour, in percent.
IF OBJECT_ID(N'fact.national_mix') IS NULL
CREATE TABLE fact.national_mix (
    period_start_utc  DATETIME2(0)  NOT NULL,
    fuel_id           TINYINT       NOT NULL CONSTRAINT FK_national_mix_fuel REFERENCES dim.fuel (fuel_id),
    date_key          INT           NOT NULL,
    half_hour         TINYINT       NOT NULL,
    share_pct         DECIMAL(4, 1) NOT NULL,
    CONSTRAINT PK_fact_national_mix PRIMARY KEY (period_start_utc, fuel_id)
);
GO
