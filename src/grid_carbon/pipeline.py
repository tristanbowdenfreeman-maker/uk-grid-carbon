"""Download each source window to disk and log it in stg.api_raw, skipping windows already fetched in full."""

import gzip
from datetime import datetime, timedelta, timezone

import duckdb

from grid_carbon.config import RAW_DIR
from grid_carbon.sources import Downloader, Window, all_windows

# A window is final once it ended this long before it was downloaded: by then the Carbon
# Intensity API has its actual values and the weather archive has caught up (about 5 days).
SETTLE = timedelta(days=7)
CAPACITY_REFRESH = timedelta(days=7)  # NESO publishes these a few times a year


def windows_to_fetch(conn: duckdb.DuckDBPyConnection, now: datetime | None = None) -> list[Window]:
    now = now or datetime.now(timezone.utc).replace(tzinfo=None)
    rows = conn.execute("SELECT source, window_start, window_end, fetched_at FROM stg.api_raw").fetchall()
    staged = {(source, start): (end, fetched) for source, start, end, fetched in rows}
    todo = []
    for window in all_windows(now.date()):
        found = staged.get((window.source, window.start))
        if found is None:
            todo.append(window)
            continue
        end, fetched = found
        if window.source == "capacity":
            if now - fetched > CAPACITY_REFRESH:
                todo.append(window)
        elif fetched < datetime.combine(end, datetime.min.time()) + SETTLE:
            todo.append(window)  # downloaded before it settled: download it again
    return todo


def fetch(conn: duckdb.DuckDBPyConnection, downloader: Downloader | None = None, limit: int | None = None) -> int:
    downloader = downloader or Downloader(cache=RAW_DIR)
    todo = windows_to_fetch(conn)[:limit]
    for i, window in enumerate(todo, start=1):
        path = downloader.fetch(window)
        # loaded_at is cleared, so the loaders pick the window up again.
        conn.execute(
            "INSERT OR REPLACE INTO stg.api_raw VALUES (?, ?, ?, ?, ?, NULL)",
            [window.source, window.start, window.end, len(gzip.compress(path.read_bytes(), 1)),
             datetime.now(timezone.utc).replace(tzinfo=None)],
        )
        if i % 25 == 0 or i == len(todo):
            print(f"  {i:,} of {len(todo):,} windows downloaded")
    return len(todo)
