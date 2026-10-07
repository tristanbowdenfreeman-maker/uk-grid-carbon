-- Every download, one row per source and date window, exactly as the API sent it. Stored
-- GZIP-compressed (the same format as T-SQL COMPRESS); read it through stg.v_api_raw.
-- loaded_at says when the facts were last loaded from it: a re-download clears it, so the
-- load procedures pick the window up again.
IF OBJECT_ID(N'stg.api_raw') IS NULL
CREATE TABLE stg.api_raw (
    source        VARCHAR(12)    NOT NULL,
    window_start  DATE           NOT NULL,
    window_end    DATE           NOT NULL,
    payload_gz    VARBINARY(MAX) NOT NULL,
    fetched_at    DATETIME2(0)   NOT NULL CONSTRAINT DF_stg_api_raw_fetched DEFAULT SYSUTCDATETIME(),
    loaded_at     DATETIME2(0)   NULL,
    CONSTRAINT PK_stg_api_raw PRIMARY KEY (source, window_start)
);
GO

-- The sources the pipeline knows (sources.py). Recreated on every setup, so adding a source
-- only needs it listed here.
ALTER TABLE stg.api_raw DROP CONSTRAINT IF EXISTS CK_stg_api_raw_source;
ALTER TABLE stg.api_raw ADD CONSTRAINT CK_stg_api_raw_source
    CHECK (source IN ('national', 'generation', 'regional', 'weather', 'prices', 'neso_mix', 'capacity'));
GO

CREATE OR ALTER VIEW stg.v_api_raw
AS
SELECT source,
       window_start,
       window_end,
       CAST(DECOMPRESS(payload_gz) AS NVARCHAR(MAX)) AS payload,
       fetched_at,
       loaded_at
FROM stg.api_raw;
GO

CREATE OR ALTER PROCEDURE stg.usp_save_raw
    @source       VARCHAR(12),
    @window_start DATE,
    @window_end   DATE,
    @payload_gz   VARBINARY(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE stg.api_raw
    SET window_end = @window_end, payload_gz = @payload_gz, fetched_at = SYSUTCDATETIME(), loaded_at = NULL
    WHERE source = @source AND window_start = @window_start;

    IF @@ROWCOUNT = 0
        INSERT stg.api_raw (source, window_start, window_end, payload_gz)
        VALUES (@source, @window_start, @window_end, @payload_gz);
END;
GO
