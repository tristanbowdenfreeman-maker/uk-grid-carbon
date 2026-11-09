"""The DuckDB warehouse: opening it and running the scripts in sql/."""

from pathlib import Path

import duckdb

from grid_carbon.config import DB_PATH, SQL_DIR


def connect(path: Path | str | None = None) -> duckdb.DuckDBPyConnection:
    path = Path(path or DB_PATH)
    if str(path) != ":memory:":
        path.parent.mkdir(parents=True, exist_ok=True)
    conn = duckdb.connect(str(path))
    conn.execute("SET TimeZone = 'UTC'")
    return conn


def sql_files(sql_dir: Path = SQL_DIR) -> list[Path]:
    """Every script in sql/, in the order it runs: folder by folder, then file by file."""
    return sorted(sql_dir.glob("[0-9]_*/[0-9][0-9]_*.sql"))


def run_scripts(conn: duckdb.DuckDBPyConnection, sql_dir: Path = SQL_DIR, verbose: bool = False) -> None:
    """Create or update the tables and views. Safe to run on every refresh."""
    for path in sql_files(sql_dir):
        conn.execute(path.read_text())
        if verbose:
            print(f"  ran {path.parent.name}/{path.name}")
