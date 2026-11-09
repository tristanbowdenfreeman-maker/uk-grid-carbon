"""Export the mart views to JSON for the website (site/data).

The website is plain files on GitHub Pages, so it can't query the database; it reads these
instead. Every file is aggregated: the biggest is a few hundred KB. The daily job publishes the
folder to the repository's GitHub Pages site, which is where the live site reads it from.
"""

import json
from datetime import date, datetime, timezone

import duckdb
import pandas as pd

from grid_carbon.config import EXPORT_DIR

# Each view and the order its rows are written in (views have no ORDER BY).
MART_VIEWS = {
    "v_summary": None,
    "v_gb_annual": "period",
    "v_on_track": None,
    "v_capacity": "technology, basis, year",
    "v_region_summary": "period, region_id",
    "v_region_profile": "region_id, season, hour_uk",
    "v_region_wind": "region_id, band_order",
}
LOOKUPS = {
    "data_checks": "SELECT check_name, is_blocking, failures FROM etl.v_data_quality_checks",
}


def _frames(conn: duckdb.DuckDBPyConnection) -> dict[str, pd.DataFrame]:
    frames = {
        view.removeprefix("v_"): conn.execute(f"SELECT * FROM mart.{view}" + (f" ORDER BY {order}" if order else "")).df()
        for view, order in MART_VIEWS.items()
    }
    frames.update({name: conn.execute(query).df() for name, query in LOOKUPS.items()})
    return frames


def _dates_as_days(frame: pd.DataFrame) -> pd.DataFrame:
    """Write date-only columns as YYYY-MM-DD. A timestamp with no time zone is read by browsers as
    local time, which in British summer time puts the 1st of a month in the month before."""
    for column in frame.columns:
        values = frame[column]
        if values.dtype == object and values.map(lambda v: isinstance(v, date) and not isinstance(v, datetime)).all():
            values = pd.to_datetime(values)
        if pd.api.types.is_datetime64_any_dtype(values) and (values.dropna() == values.dropna().dt.normalize()).all():
            frame[column] = values.dt.strftime("%Y-%m-%d")
    return frame


def export(conn: duckdb.DuckDBPyConnection, directory=EXPORT_DIR) -> None:
    """Write one JSON file per mart view, plus meta.json with the time of the export."""
    files = {
        f"{name}.json": _dates_as_days(frame).to_json(orient="records", double_precision=4, date_format="iso")
        for name, frame in _frames(conn).items()
    }
    files["meta.json"] = json.dumps({"exported_at": datetime.now(timezone.utc).isoformat(timespec="seconds")})
    directory.mkdir(parents=True, exist_ok=True)
    for name, body in files.items():
        (directory / name).write_text(body)
        print(f"  {directory.name}/{name}: {len(body) / 1024:,.0f} KB")
