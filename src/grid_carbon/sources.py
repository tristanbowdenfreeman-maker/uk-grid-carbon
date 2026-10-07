"""The public APIs this project downloads from. None of them need a key.

Each source is split into fixed date windows, the unit that gets downloaded and staged:
  national    National Grid ESO Carbon Intensity API, forecast and actual intensity for Great Britain
  generation  the same API, Great Britain's generation mix
  regional    the same API, estimated intensity and generation mix for each of the 14 DNO regions
  weather     Open-Meteo's historical archive (ERA5), hourly wind, sunshine and temperature
  neso_mix    NESO's historic generation mix: megawatts from each fuel in Great Britain, half-hourly
              since 2009 (the backbone of "are we on track for clean power by 2030?")
  capacity    NESO's installed capacity by technology: each Future Energy Scenarios edition's
              latest actual year and its 2030 outlook, plus the Clean Power 2030 portfolio
  prices      Octopus Energy's Agile tariff: a half-hourly electricity price for each region, set the
              day before from wholesale prices
"""

import time
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

import requests

CARBON_API = "https://api.carbonintensity.org.uk"
WEATHER_API = "https://archive-api.open-meteo.com/v1/archive"
NESO_API = "https://api.neso.energy/api/3/action"
NESO_MIX = "f93d1835-75bc-43e5-84ad-12472b180a98"  # Historic GB generation mix
NESO_MIX_FIRST_DAY = date(2009, 1, 1)
NESO_MIX_COLUMNS = ["DATETIME", "GAS", "COAL", "NUCLEAR", "WIND", "WIND_EMB", "HYDRO", "IMPORTS", "BIOMASS",
                    "OTHER", "SOLAR", "STORAGE"]
# Future Energy Scenarios, table ES1 (electricity supply), one resource per yearly edition. Each
# edition's first year column is the latest actual. Add next July's edition here when it's out.
NESO_FES = {
    2020: "40f40b39-5eba-4479-94b1-328ea9b8eefe",
    2021: "bca9679e-9860-4efd-9145-220d7dc4b912",
    2022: "90c4a0e8-22fd-4bda-b5bd-14a540893a98",
    2023: "86812136-3f52-43e5-8f7c-7e4f6d5f95fc",
    2024: "8c8a436d-408a-441b-8c7a-84249805772c",
    2025: "6c78a777-b885-4bb6-bc35-8100f9e137a2",
    2026: "b3bf8ac0-d27a-447c-975c-208ae92c0fa5",
}
# Resource Adequacy in the 2030s: the "Starting point" portfolio is NESO's Clean Power 2030 mix.
NESO_ADEQUACY = "c2bba528-b75a-42c5-bb98-3af3a5b3f720"
OCTOPUS_API = "https://api.octopus.energy/v1"

# The first day all three Carbon Intensity datasets have data.
FIRST_DAY = date(2018, 5, 11)
HOURLY_WEATHER = "wind_speed_100m,shortwave_radiation,temperature_2m"

# One weather point per DNO region (a central town), plus Dogger Bank in the North Sea, where most
# of Britain's offshore wind is. Kept in step with sql/2_model/03_dim_weather_point.sql.
WEATHER_POINTS = [
    (1, 57.48, -4.22), (2, 55.60, -3.60), (3, 53.48, -2.24), (4, 54.97, -1.61), (5, 53.80, -1.55),
    (6, 53.20, -3.30), (7, 51.70, -3.50), (8, 52.48, -1.90), (9, 52.95, -1.15), (10, 52.40, 0.90),
    (11, 50.72, -3.53), (12, 51.10, -1.30), (13, 51.51, -0.13), (14, 51.20, 0.70), (15, 54.75, 1.90),
]


# Octopus prices each region separately, by a letter (its GSP group). Letter -> Carbon Intensity
# API region_id; kept in step with tariff_region in sql/2_model/02_dim_region.sql.
TARIFF_REGIONS = {
    "A": 10, "B": 9, "C": 13, "D": 6, "E": 8, "F": 4, "G": 3,
    "H": 12, "J": 14, "K": 7, "L": 11, "M": 5, "N": 2, "P": 1,
}

# The Agile tariff on sale to new customers, and the day each version went on sale. Agile was
# withdrawn from 6 October to 25 November 2022; the previous version is used for those weeks (its
# prices kept being published for existing customers). A version launched after this list is
# found through the API (agile_products).
AGILE_PRODUCTS = [
    (date(2017, 1, 1), "AGILE-18-02-21"),
    (date(2022, 7, 22), "AGILE-22-07-22"),
    (date(2022, 8, 29), "AGILE-22-08-31"),
    (date(2022, 11, 25), "AGILE-FLEX-22-11-25"),
    (date(2023, 12, 11), "AGILE-23-12-06"),
    (date(2024, 4, 3), "AGILE-24-04-03"),
    (date(2024, 10, 1), "AGILE-24-10-01"),
]


@dataclass(frozen=True)
class Window:
    source: str
    start: date
    end: date  # exclusive


def _windows(source: str, first: date, days: int, today: date) -> list[Window]:
    windows, start = [], first
    while start <= today:
        windows.append(Window(source, start, start + timedelta(days=days)))
        start += timedelta(days=days)
    return windows


def _month_windows(source: str, first: date, today: date) -> list[Window]:
    windows, start = [], first.replace(day=1)
    while start <= today:
        end = (start + timedelta(days=32)).replace(day=1)
        windows.append(Window(source, start, end))
        start = end
    return windows


def all_windows(today: date | None = None) -> list[Window]:
    """Every window from FIRST_DAY to today. The API allows 14 days nationally and 7 regionally."""
    today = today or datetime.now(timezone.utc).date()
    return [
        *_windows("national", FIRST_DAY, 14, today),
        *_windows("generation", FIRST_DAY, 14, today),
        *_windows("regional", FIRST_DAY, 7, today),
        *_month_windows("weather", FIRST_DAY, today),
        *_month_windows("prices", FIRST_DAY, today),
        *_month_windows("neso_mix", NESO_MIX_FIRST_DAY, today),
        Window("capacity", date(2019, 1, 1), today),
    ]


class Downloader:
    """A requests session with retries; pauses between calls to stay polite to free APIs.

    With a cache folder (local runs use raw/), settled windows are kept on disk, so rebuilding
    the database doesn't download eight years of data again.
    """

    def __init__(self, pause: float = 0.3, cache: Path | None = None):
        self.session = requests.Session()
        self.session.headers["User-Agent"] = "uk-grid-carbon (portfolio project)"
        self.pause = pause
        self.cache = cache

    def get(self, url: str, params: dict | None = None) -> requests.Response:
        for attempt in range(5):
            response = self.session.get(url, params=params, timeout=60)
            if response.status_code < 500 and response.status_code != 429:
                response.raise_for_status()
                time.sleep(self.pause)
                return response
            time.sleep(5 * 2**attempt)
        response.raise_for_status()
        return response

    def fetch(self, window: Window) -> str:
        """The window's data as a JSON string, as the API sent it."""
        settled = window.source != "capacity" and window.end + timedelta(days=7) < datetime.now(timezone.utc).date()
        path = self.cache / window.source / f"{window.start.isoformat()}.json" if self.cache else None
        if path and settled and path.exists():
            return path.read_text()
        payload = self._download(window)
        if path and settled:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(payload)
        return payload

    def _download(self, window: Window) -> str:
        stamp = "%Y-%m-%dT%H:%MZ"
        frm = datetime.combine(window.start, datetime.min.time()).strftime(stamp)
        to = datetime.combine(window.end, datetime.min.time()).strftime(stamp)
        if window.source == "national":
            return self.get(f"{CARBON_API}/intensity/{frm}/{to}").text
        if window.source == "generation":
            return self.get(f"{CARBON_API}/generation/{frm}/{to}").text
        if window.source == "regional":
            return self.get(f"{CARBON_API}/regional/intensity/{frm}/{to}").text
        if window.source == "weather":
            end = min(window.end - timedelta(days=1), datetime.now(timezone.utc).date())
            return self.get(WEATHER_API, {
                "latitude": ",".join(str(p[1]) for p in WEATHER_POINTS),
                "longitude": ",".join(str(p[2]) for p in WEATHER_POINTS),
                "start_date": window.start.isoformat(),
                "end_date": end.isoformat(),
                "hourly": HOURLY_WEATHER,
                "wind_speed_unit": "ms",
                "timezone": "UTC",
            }).text
        if window.source == "neso_mix":
            columns = ", ".join(f'"{c}"' for c in NESO_MIX_COLUMNS)
            sql = (f'SELECT {columns} FROM "{NESO_MIX}" WHERE "DATETIME" >= \'{window.start.isoformat()}\' '
                   f'AND "DATETIME" < \'{window.end.isoformat()}\' ORDER BY "DATETIME"')
            return self.get(f"{NESO_API}/datastore_search_sql", {"sql": sql}).text
        if window.source == "capacity":
            return self._download_capacity()
        if window.source == "prices":
            return self._download_prices(window)
        raise ValueError(f"Unknown source {window.source}")

    def _download_capacity(self) -> str:
        """{"fes": {edition: [ES1 rows]}, "adequacy": [Starting point rows]}, rows as NESO sends them."""
        import json

        def rows(resource: str, **params) -> list[dict]:
            return self.get(f"{NESO_API}/datastore_search", {"resource_id": resource, "limit": 5000, **params}).json()["result"]["records"]

        return json.dumps({
            "fes": {str(edition): rows(resource) for edition, resource in NESO_FES.items()},
            "adequacy": rows(NESO_ADEQUACY, filters=json.dumps({"Name": "Starting point"})),
        }, separators=(",", ":"))

    def agile_products(self) -> list[tuple[date, str]]:
        """AGILE_PRODUCTS, plus the version on sale now if Octopus has launched a new one."""
        if not hasattr(self, "_agile"):
            self._agile = list(AGILE_PRODUCTS)
            products = self.get(f"{OCTOPUS_API}/products/", {"brand": "OCTOPUS_ENERGY", "page_size": 1500}).json()
            for product in products["results"]:
                code = product["code"]
                if code.startswith("AGILE") and "OUTGOING" not in code and code not in dict(map(reversed, self._agile)):
                    self._agile.append((date.fromisoformat(product["available_from"][:10]), code))
            self._agile.sort()
        return self._agile

    def _download_prices(self, window: Window) -> str:
        """Every region's half-hourly Agile prices in the window, split where the version changes:
        {"parts": [{"product", "from", "to", "regions": {letter: [rates]}}]}."""
        import json

        products = self.agile_products()
        parts = []
        for i, (on_sale, code) in enumerate(products):
            until = products[i + 1][0] if i + 1 < len(products) else date.max
            start, end = max(window.start, on_sale), min(window.end, until)
            if start >= end:
                continue
            regions = {}
            for letter in TARIFF_REGIONS:
                url = f"{OCTOPUS_API}/products/{code}/electricity-tariffs/E-1R-{code}-{letter}/standard-unit-rates/"
                params = {"period_from": f"{start.isoformat()}T00:00Z", "period_to": f"{end.isoformat()}T00:00Z", "page_size": 1500}
                rates = []
                while url:
                    page = self.get(url, params).json()
                    rates += [{"from": r["valid_from"], "p": r["value_inc_vat"]} for r in page["results"]]
                    url, params = page["next"], None
                regions[letter] = rates
            parts.append({"product": code, "from": start.isoformat(), "to": end.isoformat(), "regions": regions})
        return json.dumps({"parts": parts}, separators=(",", ":"))
