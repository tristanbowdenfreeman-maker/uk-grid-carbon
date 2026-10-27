"""Download the hazard data for the climate risk model. None of it needs a key.

  gusts        Open-Meteo's historical archive (ERA5): the strongest gust each day at each region's
               weather point, from 1979, the start of the reliable ERA5 period
  flood areas  the Environment Agency's flood warning areas, each with a centre point, placed in a
               DNO region using NESO's licence area boundaries
  warnings     the Environment Agency's historic flood warnings since 2006 (England only), a
               spreadsheet inside a ZIP, updated quarterly

Everything lands in raw/climate_risk/. Run with: python climate_risk/fetch.py
"""

import io
import json
import sys
import zipfile
from datetime import date
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
from grid_carbon.sources import TARIFF_REGIONS, WEATHER_API, WEATHER_POINTS, Downloader  # noqa: E402

RAW = Path(__file__).resolve().parents[1] / "raw" / "climate_risk"
FLOOD_AREAS_API = "https://environment.data.gov.uk/flood-monitoring/id/floodAreas"
# NESO's DNO licence area boundaries in British National Grid metres, the same file tools/build_map.py draws.
DNO_AREAS = ("https://api.neso.energy/dataset/0e377f16-95e9-4c15-a1fc-49e06a39cfa0/resource/"
             "1c6a7dc0-1b6c-443a-bc67-5f7125649434/download/gb-dno-license-areas-20240503-as-geojson.geojson")
WARNINGS_ZIP = ("https://environment.data.gov.uk/api/file/download"
                "?fileDataSetId=766cb094-b392-4bd6-a02e-f60e143f3213&fileName=Historic_Flood_Warnings.zip")
FIRST_YEAR = 1979


def fetch_gusts(downloader: Downloader, today: date) -> pd.DataFrame:
    """One row per region per day: the day's strongest 10 m gust in m/s. Fetched a decade at a time."""
    points = [p for p in WEATHER_POINTS if p[0] <= 14]  # the 14 DNO regions, not Dogger Bank
    frames = []
    for start in range(FIRST_YEAR, today.year + 1, 10):
        end = min(date(start + 9, 12, 31), today)
        payload = downloader.get(WEATHER_API, {
            "latitude": ",".join(str(p[1]) for p in points),
            "longitude": ",".join(str(p[2]) for p in points),
            "start_date": f"{start}-01-01",
            "end_date": end.isoformat(),
            "daily": "wind_gusts_10m_max",
            "wind_speed_unit": "ms",
            "timezone": "Europe/London",
        }).json()
        for (region_id, _, _), location in zip(points, payload):
            frames.append(pd.DataFrame({
                "region_id": region_id,
                "day": pd.to_datetime(location["daily"]["time"]),
                "gust_ms": location["daily"]["wind_gusts_10m_max"],
            }))
    return pd.concat(frames, ignore_index=True).dropna()


def fetch_flood_areas(downloader: Downloader) -> pd.DataFrame:
    """Each flood area's centre point, and the DNO region it falls in (or the nearest one, for the
    few centre points just off the coast)."""
    from pyproj import Transformer
    from shapely.geometry import Point, shape

    items = downloader.get(FLOOD_AREAS_API, {"_limit": 10000}).json()["items"]
    regions = {
        TARIFF_REGIONS[f["properties"]["Name"].lstrip("_")]: shape(f["geometry"])
        for f in downloader.get(DNO_AREAS).json()["features"]
    }
    to_bng = Transformer.from_crs("EPSG:4326", "EPSG:27700", always_xy=True)
    rows = []
    for item in items:
        point = Point(to_bng.transform(item["long"], item["lat"]))
        region_id = min(regions, key=lambda r: regions[r].distance(point))
        rows.append({"code": item["notation"], "lat": item["lat"], "lon": item["long"], "region_id": region_id})
    return pd.DataFrame(rows)


def fetch_warnings(downloader: Downloader) -> pd.DataFrame:
    archive = zipfile.ZipFile(io.BytesIO(downloader.get(WARNINGS_ZIP).content))
    sheet = next(n for n in archive.namelist() if n.endswith(".ods"))
    table = pd.read_excel(archive.open(sheet), engine="odf")
    table.columns = ["issued", "ea_area", "code", "name", "type"]
    return table


def main() -> None:
    RAW.mkdir(parents=True, exist_ok=True)
    downloader = Downloader()
    today = date.today()
    fetch_gusts(downloader, today).to_parquet(RAW / "gusts.parquet")
    fetch_flood_areas(downloader).to_parquet(RAW / "flood_areas.parquet")
    fetch_warnings(downloader).to_parquet(RAW / "warnings.parquet")
    print(json.dumps({p.name: p.stat().st_size for p in RAW.glob("*.parquet")}))


if __name__ == "__main__":
    main()
