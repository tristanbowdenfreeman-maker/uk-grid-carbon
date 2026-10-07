-- Great Britain's carbon intensity for each half-hour settlement period, in grams of CO2 per kWh.
-- forecast is National Grid ESO's day-ahead forecast; actual is its estimate from metered
-- generation, filled in after the period. period_start_uk and half_hour (0-47) are UK local time,
-- worked out once here so the marts don't convert time zones on every query.
IF OBJECT_ID(N'fact.national_intensity') IS NULL
CREATE TABLE fact.national_intensity (
    period_start_utc  DATETIME2(0) NOT NULL CONSTRAINT PK_fact_national_intensity PRIMARY KEY,
    period_start_uk   DATETIME2(0) NOT NULL,
    date_key          INT          NOT NULL CONSTRAINT FK_national_intensity_date REFERENCES dim.date (date_key),
    half_hour         TINYINT      NOT NULL,
    forecast          SMALLINT     NULL,
    actual            SMALLINT     NULL,
    intensity_index   VARCHAR(10)  NULL
);
GO
