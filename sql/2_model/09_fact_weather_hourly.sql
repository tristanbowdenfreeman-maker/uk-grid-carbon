-- Hourly weather at each weather point: wind speed 100 m up (about hub height of a wind turbine),
-- in metres per second; incoming solar radiation at the surface in watts per square metre; and
-- air temperature in degrees Celsius.
IF OBJECT_ID(N'fact.weather_hourly') IS NULL
CREATE TABLE fact.weather_hourly (
    hour_start_utc     DATETIME2(0)  NOT NULL,
    point_id           TINYINT       NOT NULL CONSTRAINT FK_weather_hourly_point REFERENCES dim.weather_point (point_id),
    wind_speed_100m    DECIMAL(4, 1) NULL,
    solar_radiation    SMALLINT      NULL,
    temperature_c      DECIMAL(4, 1) NULL,
    CONSTRAINT PK_fact_weather_hourly PRIMARY KEY (hour_start_utc, point_id)
);
GO
