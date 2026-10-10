"""Azure SQL connections and the runner for the scripts in sql/."""

import re
import time
from pathlib import Path

import pymssql
from sqlalchemy import URL, Engine, create_engine

from grid_carbon.config import PROJECT_ROOT, Settings

SQL_DIR = PROJECT_ROOT / "sql"
_GO_LINE = re.compile(r"^\s*GO\s*;?\s*$", re.IGNORECASE | re.MULTILINE)


def connect(settings: Settings, autocommit: bool = True, wake_wait: int = 300) -> pymssql.Connection:
    # Azure SQL only accepts encrypted connections, which needs TDS 7.4. A paused serverless
    # database turns logins away straight away with error 40613 while it wakes (a minute or two),
    # so keep trying for up to `wake_wait` seconds.
    deadline = time.monotonic() + wake_wait
    while True:
        try:
            return pymssql.connect(
                server=settings.mssql_host,
                port=settings.mssql_port,
                user=settings.mssql_user,
                password=settings.mssql_password,
                database=settings.mssql_database,
                autocommit=autocommit,
                tds_version="7.4",
                login_timeout=90,
                timeout=1800,
            )
        except pymssql.OperationalError as error:
            if not _is_waking(error) or time.monotonic() > deadline:
                raise
            time.sleep(15)


def _is_waking(error: pymssql.OperationalError) -> bool:
    """True for error 40613, which a paused database returns while it wakes up."""
    detail = error.args[0] if error.args else None
    return isinstance(detail, tuple) and detail[0] == 40613


def engine(settings: Settings) -> Engine:
    """SQLAlchemy engine, used by pandas for the JSON export."""
    return create_engine(
        URL.create(
            "mssql+pymssql",
            username=settings.mssql_user,
            password=settings.mssql_password,
            host=settings.mssql_host,
            port=settings.mssql_port,
            database=settings.mssql_database,
            query={"tds_version": "7.4", "login_timeout": "90"},
        )
    )


def split_batches(script: str) -> list[str]:
    """Split a T-SQL script on GO lines, the way sqlcmd and SSMS do."""
    return [batch.strip() for batch in _GO_LINE.split(script) if batch.strip()]


def sql_files(sql_dir: Path = SQL_DIR) -> list[Path]:
    """Every script in sql/, in the order it runs: folder by folder, then file by file."""
    return sorted(sql_dir.glob("[0-9]_*/[0-9][0-9]_*.sql"))


def run_scripts(settings: Settings, sql_dir: Path = SQL_DIR) -> None:
    """Run every script in sql/. The database itself is created by infra/deploy.sh."""
    with connect(settings) as conn:
        cursor = conn.cursor()
        for path in sql_files(sql_dir):
            for batch in split_batches(path.read_text()):
                cursor.execute(batch)
            print(f"  ran {path.parent.name}/{path.name}")
