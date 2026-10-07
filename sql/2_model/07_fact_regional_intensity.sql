-- Estimated carbon intensity of each region's electricity for each half-hour. The API only has an
-- estimate (it calls it the forecast) at regional level, no metered actual.
IF OBJECT_ID(N'fact.regional_intensity') IS NULL
CREATE TABLE fact.regional_intensity (
    period_start_utc  DATETIME2(0) NOT NULL,
    region_id         TINYINT      NOT NULL CONSTRAINT FK_regional_intensity_region REFERENCES dim.region (region_id),
    date_key          INT          NOT NULL,
    half_hour         TINYINT      NOT NULL,
    intensity         SMALLINT     NOT NULL,
    intensity_index   VARCHAR(10)  NULL,
    CONSTRAINT PK_fact_regional_intensity PRIMARY KEY (period_start_utc, region_id)
);
GO
