"""Download each source window into stg.api_raw, skipping windows already staged in full."""

import gzip
from datetime import datetime, timedelta, timezone

import pymssql

from grid_carbon.config import PROJECT_ROOT
from grid_carbon.sources import Downloader, Window, all_windows

CACHE_DIR = PROJECT_ROOT / "raw"  # local runs only (see Downloader)

# A window is final once it ended this long before it was downloaded: by then the Carbon
# Intensity API has its actual values and the weather archive has caught up (about 5 days).
SETTLE = timedelta(days=7)
CAPACITY_REFRESH = timedelta(days=7)  # NESO publishes these a few times a year


def windows_to_fetch(conn: pymssql.Connection, now: datetime | None = None) -> list[Window]:
    now = now or datetime.now(timezone.utc).replace(tzinfo=None)
    cursor = conn.cursor()
    cursor.execute("SELECT source, window_start, window_end, fetched_at FROM stg.api_raw")
    staged = {(source, start): (end, fetched) for source, start, end, fetched in cursor.fetchall()}
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


def fetch(conn: pymssql.Connection, downloader: Downloader | None = None, limit: int | None = None) -> int:
    downloader = downloader or Downloader(cache=CACHE_DIR if CACHE_DIR.parent.joinpath("pyproject.toml").exists() else None)
    todo = windows_to_fetch(conn)[:limit]
    cursor = conn.cursor()
    for i, window in enumerate(todo, start=1):
        payload = downloader.fetch(window)
        # Stored GZIP-compressed, the same format as T-SQL COMPRESS, so DECOMPRESS reads it.
        cursor.execute(
            "EXEC stg.usp_save_raw @source = %s, @window_start = %s, @window_end = %s, @payload_gz = %s",
            (window.source, window.start, window.end, gzip.compress(payload.encode("utf-16-le"))),
        )
        if i % 25 == 0 or i == len(todo):
            print(f"  {i:,} of {len(todo):,} windows downloaded")
    return len(todo)
