from datetime import date, datetime

from grid_carbon import pipeline
from grid_carbon.warehouse import connect, run_scripts


def make(tmp_path):
    conn = connect(tmp_path / "t.duckdb")
    run_scripts(conn)
    return conn


def test_scripts_are_rerunnable_and_build_dimensions(tmp_path):
    conn = make(tmp_path)
    run_scripts(conn)
    assert conn.execute("SELECT COUNT(*) FROM dim.region").fetchone()[0] == 18
    assert conn.execute("SELECT COUNT(*) FROM dim.fuel").fetchone()[0] == 10


def test_uk_time_macros_follow_british_summer_time(tmp_path):
    conn = make(tmp_path)
    key, half_hour = conn.execute(
        "SELECT etl.uk_date_key(TIMESTAMP '2024-03-31 23:30:00'), etl.uk_half_hour(TIMESTAMP '2024-03-31 23:30:00')"
    ).fetchone()
    assert (key, half_hour) == (20240401, 1)


def test_settled_windows_are_not_fetched_again_but_early_ones_are(tmp_path):
    conn = make(tmp_path)
    now = datetime(2026, 10, 20, 12)
    old = next(w for w in pipeline.windows_to_fetch(conn, now) if w.source == "national")
    # downloaded a week after it ended: final
    conn.execute("INSERT INTO stg.api_raw VALUES (?, ?, ?, 1, ?, NULL)", [old.source, old.start, old.end, datetime(2026, 10, 19)])
    assert old not in pipeline.windows_to_fetch(conn, now)
    # downloaded the day it ended: not settled, so fetched again
    conn.execute("UPDATE stg.api_raw SET fetched_at = ?", [datetime.combine(old.end, datetime.min.time())])
    assert old in pipeline.windows_to_fetch(conn, now)
