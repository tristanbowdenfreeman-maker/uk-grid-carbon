"""Command line: python -m grid_carbon <command>. Run with no arguments for the list of commands."""

import argparse
import sys

from grid_carbon import pipeline
from grid_carbon.config import RAW_DIR
from grid_carbon.export import export
from grid_carbon.sources import Downloader
from grid_carbon.transform import failed_checks, transform
from grid_carbon.warehouse import connect, run_scripts


def _print_rows(cursor) -> None:
    columns = [c[0] for c in cursor.description]
    rows = cursor.fetchall()
    widths = [max(len(str(v)) for v in [col, *(r[i] for r in rows)]) for i, col in enumerate(columns)]
    print("  " + "  ".join(c.ljust(w) for c, w in zip(columns, widths)))
    for row in rows:
        print("  " + "  ".join(str(v).ljust(w) for v, w in zip(row, widths)))


def cmd_setup_db(conn, args):
    run_scripts(conn, verbose=True)


def cmd_fetch(conn, args):
    count = pipeline.fetch(conn, limit=args.limit)
    print(f"Downloaded {count:,} windows")


def cmd_transform(conn, args):
    transform(conn, Downloader(cache=RAW_DIR))


def cmd_check(conn, args):
    failures = failed_checks(conn)
    for name, blocking, count in failures:
        print(f"  {'FAIL' if blocking else 'note'}  {name}: {count:,}")
    if any(blocking for _, blocking, _ in failures):
        raise SystemExit("Blocking data checks failed: not exporting")
    print("Data checks passed")


def cmd_export(conn, args):
    export(conn)


def cmd_run(conn, args):
    """Everything the daily job does: fetch, transform, check, export."""
    cmd_fetch(conn, args)
    cmd_transform(conn, args)
    cmd_check(conn, args)
    cmd_export(conn, args)


def cmd_status(conn, args):
    _print_rows(conn.execute("""
        SELECT source, COUNT(*) AS windows, COUNT(*) FILTER (WHERE loaded_at IS NULL) AS not_loaded,
               MIN(window_start) AS first_window, MAX(window_end) AS last_window,
               CAST(SUM(compressed_bytes) / 1048576.0 AS DECIMAL(9, 1)) AS mb_compressed
        FROM stg.api_raw GROUP BY source ORDER BY source"""))
    print()
    _print_rows(conn.execute("""
        SELECT 'national_intensity' AS fact, COUNT(*) AS row_count FROM fact.national_intensity
        UNION ALL SELECT 'national_mix', COUNT(*) FROM fact.national_mix
        UNION ALL SELECT 'regional_intensity', COUNT(*) FROM fact.regional_intensity
        UNION ALL SELECT 'regional_mix', COUNT(*) FROM fact.regional_mix
        UNION ALL SELECT 'weather_hourly', COUNT(*) FROM fact.weather_hourly
        UNION ALL SELECT 'price', COUNT(*) FROM fact.price
        UNION ALL SELECT 'gb_generation', COUNT(*) FROM fact.gb_generation
        UNION ALL SELECT 'capacity', COUNT(*) FROM fact.capacity"""))


COMMANDS = {
    "setup-db": (cmd_setup_db, "create or update the tables and views"),
    "fetch": (cmd_fetch, "download every window not fetched yet, or fetched before it settled"),
    "transform": (cmd_transform, "load the facts from the downloaded windows"),
    "check": (cmd_check, "run the data-quality checks"),
    "export": (cmd_export, "write the mart views to site/data"),
    "run": (cmd_run, "fetch, transform, check and export (what the daily job runs)"),
    "status": (cmd_status, "downloads and row counts"),
}


def main(argv=None) -> None:
    parser = argparse.ArgumentParser(prog="python -m grid_carbon")
    sub = parser.add_subparsers(dest="command")
    for name, (_, help_text) in COMMANDS.items():
        p = sub.add_parser(name, help=help_text)
        if name in ("fetch", "run"):
            p.add_argument("--limit", type=int, help="download at most this many windows")
    args = parser.parse_args(argv)
    if not args.command:
        parser.print_help()
        sys.exit(1)
    conn = connect()
    try:
        run_scripts(conn)  # idempotent, so a new or older warehouse is brought up to date first
        COMMANDS[args.command][0](conn, args)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
