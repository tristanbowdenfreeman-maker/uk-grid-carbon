-- Objects from earlier versions of the dashboard, removed when it was refocused on Clean Power
-- 2030 (October 2026): the Met Office temperature record and the old per-chart views.
-- Safe to run on a new database, where none of them exist.
DROP VIEW IF EXISTS mart.v_national_period, mart.v_national_monthly, mart.v_national_mix_monthly,
                    mart.v_region_hourly, mart.v_heatmap, mart.v_wind_band, mart.v_forecast_accuracy,
                    mart.v_day_profile, mart.v_cet_annual, mart.v_extremes, mart.v_charging_slot,
                    mart.v_charging_curve, mart.v_price_monthly;
GO
DROP PROCEDURE IF EXISTS etl.usp_load_cet;
DROP TABLE IF EXISTS fact.cet_monthly;
GO
IF OBJECT_ID(N'stg.api_raw') IS NOT NULL
    DELETE stg.api_raw WHERE source = 'cet';
GO
