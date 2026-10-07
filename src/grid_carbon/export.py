"""Export the mart views to JSON for the website, locally (site/data) and to Azure Blob Storage.

The website is plain files on GitHub Pages, so it can't query the database; it reads these
instead. Every file is aggregated: the biggest is a few hundred KB.
"""

import json
from datetime import date, datetime, timezone

import pandas as pd

from grid_carbon.config import PROJECT_ROOT, Settings
from grid_carbon.db import engine

EXPORT_DIR = PROJECT_ROOT / "site" / "data"
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


def _frames(settings: Settings) -> dict[str, pd.DataFrame]:
    eng = engine(settings)
    frames = {
        view.removeprefix("v_"): pd.read_sql(f"SELECT * FROM mart.{view}" + (f" ORDER BY {order}" if order else ""), eng)
        for view, order in MART_VIEWS.items()
    }
    frames.update({name: pd.read_sql(query, eng) for name, query in LOOKUPS.items()})
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


def export(settings: Settings, local: bool = True) -> None:
    """Write site/data (skipped on Azure, where the app's files are read-only) and upload."""
    files = {
        f"{name}.json": _dates_as_days(frame).to_json(orient="records", double_precision=4, date_format="iso")
        for name, frame in _frames(settings).items()
    }
    files["meta.json"] = json.dumps({"exported_at": datetime.now(timezone.utc).isoformat(timespec="seconds")})

    if local:
        EXPORT_DIR.mkdir(parents=True, exist_ok=True)
        for name, body in files.items():
            (EXPORT_DIR / name).write_text(body)
            print(f"  site/data/{name}: {len(body) / 1024:,.0f} KB")

    if settings.storage_connection_string:
        upload(settings, files)


def upload(settings: Settings, files: dict[str, str]) -> None:
    """Upload to the public blob container the live site reads from. Short cache, because the
    data changes once a day."""
    from azure.storage.blob import BlobServiceClient, ContentSettings

    service = BlobServiceClient.from_connection_string(settings.storage_connection_string)
    container = service.get_container_client(settings.storage_container)
    content = ContentSettings(content_type="application/json", cache_control="public, max-age=1800")
    for name, body in files.items():
        container.upload_blob(name, body.encode(), overwrite=True, content_settings=content)
    print(f"  uploaded {len(files)} files to blob container '{settings.storage_container}'")
