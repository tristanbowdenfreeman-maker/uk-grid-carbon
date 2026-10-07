"""Command line: python -m grid_carbon <command>. Run with no arguments for the list of commands."""

import argparse
import sys

from grid_carbon import pipeline
from grid_carbon.config import load_settings
from grid_carbon.db import connect, run_scripts
from grid_carbon.export import export
from grid_carbon.transform import failed_checks, transform


def _print_rows(cursor) -> None:
    columns = [c[0] for c in cursor.description]
    rows = cursor.fetchall()
    widths = [max(len(str(v)) for v in [col, *(r[i] for r in rows)]) for i, col in enumerate(columns)]
    print("  " + "  ".join(c.ljust(w) for c, w in zip(columns, widths)))
    for row in rows:
        print("  " + "  ".join(str(v).ljust(w) for v, w in zip(row, widths)))


def cmd_setup_db(settings, args):
    run_scripts(settings)


def cmd_fetch(settings, args):
    with connect(settings) as conn:
        count = pipeline.fetch(conn, limit=args.limit)
    print(f"Downloaded {count:,} windows")


def cmd_transform(settings, args):
    with connect(settings) as conn:
        transform(conn)


def cmd_check(settings, args):
    with connect(settings) as conn:
        failures = failed_checks(conn)
    for name, blocking, count in failures:
        print(f"  {'FAIL' if blocking else 'note'}  {name}: {count:,}")
    if any(blocking for _, blocking, _ in failures):
        raise SystemExit("Blocking data checks failed: not exporting")
    print("Data checks passed")


def cmd_export(settings, args):
    export(settings)


def cmd_run(settings, args):
    """Everything the scheduled Azure Function does: fetch, transform, check, export."""
    cmd_fetch(settings, args)
    cmd_transform(settings, args)
    cmd_check(settings, args)
    cmd_export(settings, args)


def cmd_status(settings, args):
    with connect(settings) as conn:
        cursor = conn.cursor()
        cursor.execute("""
            SELECT source, COUNT(*) AS windows, SUM(CASE WHEN loaded_at IS NULL THEN 1 ELSE 0 END) AS not_loaded,
                   MIN(window_start) AS first_window, MAX(window_end) AS last_window,
                   CAST(SUM(DATALENGTH(payload_gz)) / 1048576.0 AS DECIMAL(9, 1)) AS mb_compressed
            FROM stg.api_raw GROUP BY source ORDER BY source""")
        _print_rows(cursor)
        print()
        cursor.execute("""
            SELECT 'national_intensity' AS fact, COUNT_BIG(*) AS row_count FROM fact.national_intensity
            UNION ALL SELECT 'national_mix', COUNT_BIG(*) FROM fact.national_mix
            UNION ALL SELECT 'regional_intensity', COUNT_BIG(*) FROM fact.regional_intensity
            UNION ALL SELECT 'regional_mix', COUNT_BIG(*) FROM fact.regional_mix
            UNION ALL SELECT 'weather_hourly', COUNT_BIG(*) FROM fact.weather_hourly
            UNION ALL SELECT 'price', COUNT_BIG(*) FROM fact.price
            UNION ALL SELECT 'gb_generation', COUNT_BIG(*) FROM fact.gb_generation
            UNION ALL SELECT 'capacity', COUNT_BIG(*) FROM fact.capacity""")
        _print_rows(cursor)


COMMANDS = {
    "setup-db": (cmd_setup_db, "create or update the tables, procedures and views"),
    "fetch": (cmd_fetch, "download every window not staged yet, or staged before it settled"),
    "transform": (cmd_transform, "load the facts from the staged downloads"),
    "check": (cmd_check, "run the data-quality checks"),
    "export": (cmd_export, "write the mart views to site/data and Azure Blob Storage"),
    "run": (cmd_run, "fetch, transform, check and export (what the Azure Function runs)"),
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
    COMMANDS[args.command][0](load_settings(), args)


if __name__ == "__main__":
    main()
