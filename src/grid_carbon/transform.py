"""Run the load procedures in sql/3_etl, one after another (each commits as it goes)."""

import pymssql

PROCEDURES = [
    "etl.usp_load_national",
    "etl.usp_load_generation",
    "etl.usp_load_regional",
    "etl.usp_load_weather",
    "etl.usp_load_prices",
    "etl.usp_load_gb_generation",
    "etl.usp_load_capacity",
]


def transform(conn: pymssql.Connection) -> None:
    cursor = conn.cursor()
    for procedure in PROCEDURES:
        cursor.execute(f"EXEC {procedure}")
        source, rows = cursor.fetchone()
        print(f"  {source}: {rows:,} rows loaded")


def failed_checks(conn: pymssql.Connection) -> list[tuple[str, bool, int]]:
    """Every check with failures, as (name, is_blocking, failures)."""
    cursor = conn.cursor()
    cursor.execute("SELECT check_name, is_blocking, failures FROM etl.v_data_quality_checks WHERE failures > 0")
    return [(name, bool(blocking), failures) for name, blocking, failures in cursor.fetchall()]
