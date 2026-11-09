-- The fact tables. No primary keys on the big ones: DuckDB keeps a key index in memory and it
-- slows bulk loads, so each loader replaces a whole window (delete, then insert) and groups its
-- rows by the natural key instead.

-- Great Britain's carbon intensity for each half-hour settlement period, in grams of CO2 per kWh.
-- forecast is National Grid ESO's day-ahead forecast; actual is its estimate from metered
-- generation, filled in after the period. period_start_uk and half_hour (0-47) are UK local time,
-- worked out once here so the marts don't convert time zones on every query.
CREATE TABLE IF NOT EXISTS fact.national_intensity (
    period_start_utc  TIMESTAMP NOT NULL,
    period_start_uk   TIMESTAMP NOT NULL,
    date_key          INTEGER   NOT NULL,
    half_hour         TINYINT   NOT NULL,
    forecast          SMALLINT,
    actual            SMALLINT,
    intensity_index   VARCHAR
);

-- Great Britain's generation mix: the share of each fuel in each half-hour, in percent.
CREATE TABLE IF NOT EXISTS fact.national_mix (
    period_start_utc  TIMESTAMP    NOT NULL,
    fuel_id           TINYINT      NOT NULL,
    date_key          INTEGER      NOT NULL,
    half_hour         TINYINT      NOT NULL,
    share_pct         DECIMAL(4,1) NOT NULL
);

-- Estimated carbon intensity of each region's electricity for each half-hour. The API only has an
-- estimate (it calls it the forecast) at regional level, no metered actual.
CREATE TABLE IF NOT EXISTS fact.regional_intensity (
    period_start_utc  TIMESTAMP NOT NULL,
    region_id         TINYINT   NOT NULL,
    date_key          INTEGER   NOT NULL,
    half_hour         TINYINT   NOT NULL,
    intensity         SMALLINT  NOT NULL,
    intensity_index   VARCHAR
);

-- Each region's generation mix for each half-hour: 18 regions x 9 fuels x every half-hour since
-- May 2018, about 25 million rows. DuckDB stores it compressed by column.
CREATE TABLE IF NOT EXISTS fact.regional_mix (
    period_start_utc  TIMESTAMP    NOT NULL,
    region_id         TINYINT      NOT NULL,
    fuel_id           TINYINT      NOT NULL,
    date_key          INTEGER      NOT NULL,
    half_hour         TINYINT      NOT NULL,
    share_pct         DECIMAL(4,1) NOT NULL
);

-- Hourly weather at each weather point: wind speed 100 m up (about hub height of a wind turbine),
-- in metres per second; incoming solar radiation at the surface in watts per square metre; and
-- air temperature in degrees Celsius.
CREATE TABLE IF NOT EXISTS fact.weather_hourly (
    hour_start_utc   TIMESTAMP    NOT NULL,
    point_id         TINYINT      NOT NULL,
    wind_speed_100m  DECIMAL(4,1),
    solar_radiation  SMALLINT,
    temperature_c    DECIMAL(4,1)
);

-- Great Britain's generation by fuel, in megawatts, for every half-hour since 2009 (NESO's
-- historic generation mix). Wind is NESO's metered and embedded wind added together.
CREATE TABLE IF NOT EXISTS fact.gb_generation (
    period_start_utc  TIMESTAMP    NOT NULL,
    fuel_id           TINYINT      NOT NULL,
    date_key          INTEGER      NOT NULL,
    half_hour         TINYINT      NOT NULL,
    mw                DECIMAL(8,1) NOT NULL
);

-- Octopus Agile's price for each region and half-hour, in pence per kWh including VAT. Set the day
-- before from wholesale prices, so it is the price signal a business could plan charging around.
CREATE TABLE IF NOT EXISTS fact.price (
    period_start_utc  TIMESTAMP    NOT NULL,
    region_id         TINYINT      NOT NULL,
    date_key          INTEGER      NOT NULL,
    half_hour         TINYINT      NOT NULL,
    price_p_kwh       DECIMAL(7,3) NOT NULL,
    product_code      VARCHAR      NOT NULL
);

-- Installed capacity in Great Britain for the four technologies Clean Power 2030 depends on most,
-- in megawatts. Three kinds of row:
--   actual   the latest actual year in each Future Energy Scenarios edition (2019 onwards)
--   outlook  where NESO's newest ten-year outlook expects 2030 to land
--   target   NESO's Clean Power 2030 portfolio for 2030 (Resource Adequacy "Starting point")
CREATE TABLE IF NOT EXISTS fact.capacity (
    technology   VARCHAR       NOT NULL,
    year         SMALLINT      NOT NULL,
    basis        VARCHAR       NOT NULL CHECK (basis IN ('actual', 'outlook', 'target')),
    source_name  VARCHAR       NOT NULL,
    capacity_mw  DECIMAL(9,0)  NOT NULL,
    PRIMARY KEY (technology, year, basis)
);
