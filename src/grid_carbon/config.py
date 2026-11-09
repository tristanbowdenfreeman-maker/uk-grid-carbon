"""Where things live. No settings or secrets are needed: every source is a public API without a key."""

import os
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
SQL_DIR = PROJECT_ROOT / "sql"
# The warehouse is one DuckDB file. GRID_DB overrides the location (the daily job and tests do).
DB_PATH = Path(os.getenv("GRID_DB") or PROJECT_ROOT / "warehouse" / "grid.duckdb")
# Downloads kept on disk. Settled windows are reused, so rebuilding doesn't download eight years of data again.
RAW_DIR = Path(os.getenv("GRID_RAW") or PROJECT_ROOT / "raw")
# The JSON the website reads.
EXPORT_DIR = Path(os.getenv("GRID_EXPORT") or PROJECT_ROOT / "site" / "data")
