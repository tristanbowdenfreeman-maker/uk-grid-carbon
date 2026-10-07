-- One schema per layer: raw downloads, the star schema, the load procedures and the views the
-- website reads. The database itself is an Azure SQL serverless database (infra/deploy.sh).
IF SCHEMA_ID(N'stg')  IS NULL EXEC (N'CREATE SCHEMA stg');   -- raw JSON, as downloaded
GO
IF SCHEMA_ID(N'dim')  IS NULL EXEC (N'CREATE SCHEMA dim');   -- dimensions
GO
IF SCHEMA_ID(N'fact') IS NULL EXEC (N'CREATE SCHEMA fact');  -- facts
GO
IF SCHEMA_ID(N'etl')  IS NULL EXEC (N'CREATE SCHEMA etl');   -- load procedures and checks
GO
IF SCHEMA_ID(N'mart') IS NULL EXEC (N'CREATE SCHEMA mart');  -- one view per dataset on the site
GO
