"""Settings read from .env locally, or from the Function App's settings on Azure (see .env.example)."""

import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv

PROJECT_ROOT = Path(__file__).resolve().parents[2]


@dataclass(frozen=True)
class Settings:
    mssql_host: str
    mssql_port: int
    mssql_user: str
    mssql_password: str
    mssql_database: str
    storage_connection_string: str
    storage_container: str


def load_settings() -> Settings:
    load_dotenv(PROJECT_ROOT / ".env")
    password = os.getenv("MSSQL_PASSWORD", "")
    if not password:
        raise SystemExit("MSSQL_PASSWORD is not set in .env")
    return Settings(
        mssql_host=os.getenv("MSSQL_HOST", "localhost"),
        mssql_port=int(os.getenv("MSSQL_PORT", "1433")),
        mssql_user=os.getenv("MSSQL_USER", "gridadmin"),
        mssql_password=password,
        mssql_database=os.getenv("MSSQL_DATABASE", "GridCarbon"),
        storage_connection_string=os.getenv("AZURE_STORAGE_CONNECTION_STRING", ""),
        storage_container=os.getenv("AZURE_STORAGE_CONTAINER", "data"),
    )
