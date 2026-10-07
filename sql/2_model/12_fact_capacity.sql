-- Installed capacity in Great Britain for the four technologies Clean Power 2030 depends on most,
-- in megawatts. Three kinds of row:
--   actual   the latest actual year in each Future Energy Scenarios edition (2019 onwards)
--   outlook  where NESO's newest ten-year outlook expects 2030 to land
--   target   NESO's Clean Power 2030 portfolio for 2030 (Resource Adequacy "Starting point")
IF OBJECT_ID(N'fact.capacity') IS NULL
CREATE TABLE fact.capacity (
    technology   VARCHAR(16)   NOT NULL,
    [year]       SMALLINT      NOT NULL,
    basis        VARCHAR(8)    NOT NULL CONSTRAINT CK_fact_capacity_basis CHECK (basis IN ('actual', 'outlook', 'target')),
    source_name  VARCHAR(40)   NOT NULL,
    capacity_mw  DECIMAL(9, 0) NOT NULL,
    CONSTRAINT PK_fact_capacity PRIMARY KEY (technology, [year], basis)
);
GO
