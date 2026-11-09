"""Load the fact tables from the downloaded windows that haven't been loaded yet.

Each window replaces its own rows (delete, then insert, in one transaction), so a re-downloaded
window, with its actuals filled in, simply overwrites them. Where a payload holds periods outside
its window (the Carbon Intensity API includes the half-hour before the start), only periods inside
[window_start, window_end) are kept. The big sources are parsed by DuckDB's JSON reader; the small
and awkwardly shaped ones (weather, prices, capacity) in Python.
"""

import json
import re
from decimal import ROUND_HALF_UP, Decimal

import duckdb
import pandas as pd

from grid_carbon.sources import TARIFF_REGIONS, Downloader, Window

_PERIOD = "try_strptime(left(d.\"from\", 16), '%Y-%m-%dT%H:%M')"
_UK = "etl.uk_date_key(ts), etl.uk_half_hour(ts)"


def _read_json(columns: str) -> str:
    return f"read_json(?, maximum_object_size=268435456, columns={{{columns}}})"


def _pending(conn: duckdb.DuckDBPyConnection, source: str) -> list[Window]:
    rows = conn.execute(
        "SELECT window_start, window_end FROM stg.api_raw WHERE source = ? AND loaded_at IS NULL ORDER BY window_start",
        [source],
    ).fetchall()
    return [Window(source, start, end) for start, end in rows]


def _replace(conn: duckdb.DuckDBPyConnection, window: Window, tables: dict[str, str], inserts: list[str]) -> int:
    """In one transaction: clear the window from each table (table -> its time column), run the inserts
    (which read the temp table `parsed`), and mark the window loaded. Returns the rows inserted."""
    conn.execute("BEGIN")
    try:
        for table, column in tables.items():
            conn.execute(f"DELETE FROM {table} WHERE {column} >= CAST(? AS TIMESTAMP) AND {column} < CAST(? AS TIMESTAMP)",
                         [window.start, window.end])
        rows = sum(conn.execute(sql).fetchone()[0] for sql in inserts)
        conn.execute("UPDATE stg.api_raw SET loaded_at = now()::TIMESTAMP WHERE source = ? AND window_start = ?",
                     [window.source, window.start])
        conn.execute("COMMIT")
        return rows
    except BaseException:
        conn.execute("ROLLBACK")
        raise


def _in_window(window: Window) -> str:
    return f"ts >= TIMESTAMP '{window.start}' AND ts < TIMESTAMP '{window.end}'"


def load_national(conn, downloader: Downloader) -> int:
    rows = 0
    for window in _pending(conn, "national"):
        path = downloader.locate(window)
        # The source has a few impossible values (2018-19 forecasts up to 13,579 g): blank them.
        conn.execute(f"""
            CREATE OR REPLACE TEMP TABLE parsed AS
            SELECT ts, forecast, actual, intensity_index FROM (
                SELECT {_PERIOD} AS ts,
                       CASE WHEN d.intensity.forecast BETWEEN 0 AND 1000 THEN d.intensity.forecast END AS forecast,
                       CASE WHEN d.intensity.actual   BETWEEN 0 AND 1000 THEN d.intensity.actual   END AS actual,
                       d.intensity."index" AS intensity_index
                FROM (SELECT unnest(data) AS d FROM {_read_json(
                    'data: \'STRUCT("from" VARCHAR, intensity STRUCT(forecast INTEGER, actual INTEGER, "index" VARCHAR))[]\'')})
            )
            WHERE {_in_window(window)}
            QUALIFY row_number() OVER (PARTITION BY ts) = 1""", [str(path)])
        # A timestamp format the parse doesn't know would otherwise load nothing, silently.
        if conn.execute("SELECT COUNT(*) FROM parsed").fetchone()[0] == 0:
            raise RuntimeError(f"load_national: no half-hours parsed from {path}")
        rows += _replace(conn, window, {"fact.national_intensity": "period_start_utc"}, [
            f"INSERT INTO fact.national_intensity SELECT ts, etl.uk_time(ts), {_UK}, forecast, actual, intensity_index FROM parsed"])
    return rows


def load_generation(conn, downloader: Downloader) -> int:
    rows = 0
    for window in _pending(conn, "generation"):
        path = downloader.locate(window)
        conn.execute(f"""
            CREATE OR REPLACE TEMP TABLE parsed AS
            SELECT ts, mix FROM (
                SELECT {_PERIOD} AS ts, d.generationmix AS mix
                FROM (SELECT unnest(data) AS d FROM {_read_json(
                    'data: \'STRUCT("from" VARCHAR, generationmix STRUCT(fuel VARCHAR, perc DOUBLE)[])[]\'')})
            ) WHERE {_in_window(window)}""", [str(path)])
        rows += _replace(conn, window, {"fact.national_mix": "period_start_utc"}, [f"""
            INSERT INTO fact.national_mix
            SELECT ts, fu.fuel_id, {_UK}, MAX(CAST(m.perc AS DECIMAL(4, 1)))
            FROM (SELECT ts, unnest(mix) AS m FROM parsed) AS x
            JOIN dim.fuel AS fu ON fu.fuel_key = m.fuel
            GROUP BY ts, fu.fuel_id"""])
    return rows


def load_regional(conn, downloader: Downloader) -> int:
    rows = 0
    for window in _pending(conn, "regional"):
        path = downloader.locate(window)
        # The source has a few negative estimates (London, 2018-20): leave those half-hours out.
        conn.execute(f"""
            CREATE OR REPLACE TEMP TABLE parsed AS
            SELECT ts, reg.regionid AS region_id, reg.intensity.forecast AS intensity,
                   reg.intensity."index" AS intensity_index, reg.generationmix AS mix
            FROM (SELECT {_PERIOD} AS ts, unnest(d.regions) AS reg
                  FROM (SELECT unnest(data) AS d FROM {_read_json(
                      'data: \'STRUCT("from" VARCHAR, regions STRUCT(regionid TINYINT, intensity STRUCT(forecast INTEGER, "index" VARCHAR), '
                      'generationmix STRUCT(fuel VARCHAR, perc DOUBLE)[])[])[]\'')}))
            WHERE {_in_window(window)} AND intensity BETWEEN 0 AND 1000""", [str(path)])
        rows += _replace(conn, window, {"fact.regional_intensity": "period_start_utc", "fact.regional_mix": "period_start_utc"}, [
            f"""INSERT INTO fact.regional_intensity
                SELECT ts, region_id, {_UK}, MAX(intensity), MAX(intensity_index)
                FROM parsed GROUP BY ts, region_id""",
            f"""INSERT INTO fact.regional_mix
                SELECT ts, region_id, fu.fuel_id, {_UK}, MAX(CAST(m.perc AS DECIMAL(4, 1)))
                FROM (SELECT ts, region_id, unnest(mix) AS m FROM parsed) AS x
                JOIN dim.fuel AS fu ON fu.fuel_key = m.fuel
                GROUP BY ts, region_id, fu.fuel_id"""])
    return rows


def load_weather(conn, downloader: Downloader) -> int:
    """Open-Meteo returns one object per weather point, in the order of dim.weather_point, each
    holding parallel arrays: hourly.time[i] goes with hourly.wind_speed_100m[i] and so on."""
    rows = 0
    for window in _pending(conn, "weather"):
        points = json.loads(downloader.locate(window).read_text())
        frames = []
        for point_id, point in enumerate(points, start=1):
            hourly = point["hourly"]
            frames.append(pd.DataFrame({"ts": hourly["time"], "point_id": point_id, "wind": hourly["wind_speed_100m"],
                                        "solar": hourly["shortwave_radiation"], "temp": hourly["temperature_2m"]}))
        frame = pd.concat(frames)
        conn.register("weather_frame", frame)
        # Hours the archive hasn't reached yet come back as nulls; they're left out and filled in
        # when the window is downloaded again.
        conn.execute("""
            CREATE OR REPLACE TEMP TABLE parsed AS
            SELECT CAST(ts AS TIMESTAMP) AS ts, CAST(point_id AS TINYINT) AS point_id,
                   CAST(wind AS DECIMAL(4, 1)) AS wind, CAST(round(solar) AS SMALLINT) AS solar,
                   CAST(temp AS DECIMAL(4, 1)) AS temp
            FROM weather_frame WHERE wind IS NOT NULL OR solar IS NOT NULL OR temp IS NOT NULL""")
        conn.unregister("weather_frame")
        rows += _replace(conn, window, {"fact.weather_hourly": "hour_start_utc"},
                         ["INSERT INTO fact.weather_hourly SELECT ts, point_id, wind, solar, temp FROM parsed"])
    return rows


_GB_FUELS = ["wind", "solar", "hydro", "biomass", "nuclear", "imports", "other", "gas", "coal", "storage"]
_NESO_FIELDS = ", ".join(f'"{c}" VARCHAR' for c in
                         ["DATETIME", "GAS", "COAL", "NUCLEAR", "WIND", "WIND_EMB", "HYDRO", "IMPORTS", "BIOMASS", "OTHER", "SOLAR", "STORAGE"])


def load_gb_generation(conn, downloader: Downloader) -> int:
    """One row per half-hour and fuel. NESO sends numbers as text, hence TRY_CAST."""
    rows = 0
    mw = "DECIMAL(8, 1)"
    for window in _pending(conn, "neso_mix"):
        path = downloader.locate(window)
        conn.execute(f"""
            CREATE OR REPLACE TEMP TABLE periods AS
            SELECT TRY_CAST(r."DATETIME" AS TIMESTAMP) AS ts,
                   TRY_CAST(r."GAS" AS {mw}) AS gas, TRY_CAST(r."COAL" AS {mw}) AS coal,
                   TRY_CAST(r."NUCLEAR" AS {mw}) AS nuclear,
                   TRY_CAST(r."WIND" AS {mw}) + COALESCE(TRY_CAST(r."WIND_EMB" AS {mw}), 0) AS wind,
                   TRY_CAST(r."HYDRO" AS {mw}) AS hydro, TRY_CAST(r."IMPORTS" AS {mw}) AS imports,
                   TRY_CAST(r."BIOMASS" AS {mw}) AS biomass, TRY_CAST(r."OTHER" AS {mw}) AS other,
                   TRY_CAST(r."SOLAR" AS {mw}) AS solar, TRY_CAST(r."STORAGE" AS {mw}) AS storage
            FROM (SELECT unnest(result.records) AS r
                  FROM {_read_json(f"result: 'STRUCT(records STRUCT({_NESO_FIELDS})[])'")})""", [str(path)])
        conn.execute(f"CREATE OR REPLACE TEMP TABLE parsed AS "
                     f"SELECT * FROM periods WHERE {_in_window(window)}")
        unpivot = " UNION ALL ".join(f"SELECT ts, '{fuel}' AS fuel_key, {fuel} AS mw FROM parsed" for fuel in _GB_FUELS)
        rows += _replace(conn, window, {"fact.gb_generation": "period_start_utc"}, [f"""
            INSERT INTO fact.gb_generation
            SELECT v.ts, fu.fuel_id, etl.uk_date_key(v.ts), etl.uk_half_hour(v.ts), v.mw
            FROM ({unpivot}) AS v
            JOIN dim.fuel AS fu ON fu.fuel_key = v.fuel_key
            WHERE v.mw IS NOT NULL"""])
    return rows


def _price(value: float) -> float:
    """Round the way a decimal(7, 3) column does: half up, on the number as written."""
    return float(Decimal(str(value)).quantize(Decimal("0.001"), ROUND_HALF_UP))


def load_prices(conn, downloader: Downloader) -> int:
    """A window holds one part per Agile version on sale during it, and each part one array of rates
    per region letter. Each part only keeps rates inside its own dates, so versions never overlap."""
    rows = 0
    for window in _pending(conn, "prices"):
        payload = json.loads(downloader.locate(window).read_text())
        records = []
        for part in payload["parts"]:
            first, last = f"{part['from']}T00:00", f"{part['to']}T00:00"
            for letter, rates in part["regions"].items():
                region_id = TARIFF_REGIONS[letter]
                for rate in rates:
                    stamp = rate["from"][:16]
                    if first <= stamp < last:
                        records.append((stamp, region_id, _price(rate["p"]), part["product"]))
        frame = pd.DataFrame(records, columns=["ts", "region_id", "price", "product"]).drop_duplicates(["ts", "region_id"])
        conn.register("price_frame", frame)
        conn.execute("""
            CREATE OR REPLACE TEMP TABLE parsed AS
            SELECT CAST(replace(ts, 'T', ' ') AS TIMESTAMP) AS ts, CAST(region_id AS TINYINT) AS region_id,
                   CAST(price AS DECIMAL(7, 3)) AS price, product
            FROM price_frame""")
        conn.unregister("price_frame")
        rows += _replace(conn, window, {"fact.price": "period_start_utc"},
                         [f"INSERT INTO fact.price SELECT ts, region_id, {_UK}, price, product FROM parsed"])
    return rows


# Older Future Energy Scenarios editions spell technologies and the scenario column differently.
_TECHNOLOGY = {"offshore wind": "Offshore wind", "onshore wind": "Onshore wind", "solar": "Solar",
               "solar pv": "Solar", "battery": "Batteries"}
_ADEQUACY_TECHNOLOGY = {"Offshore wind": "Offshore wind", "Onshore wind": "Onshore wind", "Solar": "Solar", "Batteries": "Batteries"}


def _capacity_rows(payload: dict) -> list[tuple[str, int, str, str, float]]:
    """(technology, year, basis, source, MW) rows from {"fes": {edition: [ES1 rows]}, "adequacy": [rows]}.
    ES1 has one column per year ("2019", "2020", ...)."""
    fes = []  # (edition, scenario, technology, year, mw)
    for edition, records in payload["fes"].items():
        for record in records:
            if record.get("Variable") != "Capacity (MW)":
                continue
            scenario = record.get("Scenario") or record.get("Pathway")
            technology = _TECHNOLOGY.get(str(record.get("Type") or "").strip().lower())
            if not scenario or not technology:
                continue
            for key, value in record.items():
                if not re.fullmatch(r"[12]\d{3}", str(key)):
                    continue
                try:
                    mw = float(str(value).replace(",", ""))
                except ValueError:
                    continue
                fes.append((int(edition), scenario, technology, int(key), mw))
    latest = max(row[0] for row in fes)
    out = []

    # Each edition's first year is history, the same in every scenario: sum the connection types
    # (transmission, distribution, micro) within a scenario, then take any scenario.
    totals: dict[tuple, float] = {}
    for edition, scenario, technology, year, mw in fes:
        if year == edition - 1:
            key = (edition, scenario, technology, year)
            totals[key] = totals.get(key, 0.0) + mw
    best: dict[tuple, float] = {}
    for (edition, _, technology, year), total in totals.items():
        if total > 0:
            best[(edition, technology, year)] = max(best.get((edition, technology, year), total), total)
    out += [(technology, year, "actual", f"NESO FES {edition}", mw) for (edition, technology, year), mw in best.items()]

    # The newest edition's ten-year outlook ("Ten Year Forecast" in 2025, "Outlook" since).
    outlook: dict[str, float] = {}
    scenarios: dict[str, str] = {}
    for edition, scenario, technology, year, mw in fes:
        if edition == latest and year == 2030 and scenario.startswith("Ten Year"):
            outlook[technology] = outlook.get(technology, 0.0) + mw
            scenarios[technology] = min(scenario, scenarios.get(technology, scenario))
    out += [(technology, 2030, "outlook", f"NESO FES {latest} {scenarios[technology]}", mw) for technology, mw in outlook.items()]

    target: dict[str, float] = {}
    for record in payload["adequacy"]:
        technology = _ADEQUACY_TECHNOLOGY.get(record.get("Technology"))
        if technology and record.get("Future Year") == "2030/31":
            target[technology] = target.get(technology, 0.0) + float(record["Installed Capacity (MW)"])
    out += [(technology, 2030, "target", "NESO Clean Power 2030 portfolio", mw) for technology, mw in target.items()]
    return out


def load_capacity(conn, downloader: Downloader) -> int:
    """Replaces fact.capacity in full from the capacity window."""
    pending = _pending(conn, "capacity")
    if not pending:
        return 0
    window = pending[0]
    rows = _capacity_rows(json.loads(downloader.locate(window).read_text()))
    frame = pd.DataFrame(rows, columns=["technology", "year", "basis", "source_name", "mw"])
    conn.register("capacity_frame", frame)
    conn.execute("BEGIN")
    try:
        conn.execute("DELETE FROM fact.capacity")
        conn.execute("""INSERT INTO fact.capacity
                        SELECT technology, CAST(year AS SMALLINT), basis, source_name, CAST(mw AS DECIMAL(9, 0)) FROM capacity_frame""")
        conn.execute("UPDATE stg.api_raw SET loaded_at = now()::TIMESTAMP WHERE source = 'capacity'")
        conn.execute("COMMIT")
    except BaseException:
        conn.execute("ROLLBACK")
        raise
    finally:
        conn.unregister("capacity_frame")
    return len(rows)


LOADERS = {
    "national": load_national,
    "generation": load_generation,
    "regional": load_regional,
    "weather": load_weather,
    "prices": load_prices,
    "neso_mix": load_gb_generation,
    "capacity": load_capacity,
}


def transform(conn: duckdb.DuckDBPyConnection, downloader: Downloader) -> None:
    for source, load in LOADERS.items():
        print(f"  {source}: {load(conn, downloader):,} rows loaded")


def failed_checks(conn: duckdb.DuckDBPyConnection) -> list[tuple[str, bool, int]]:
    """Every check with failures, as (name, is_blocking, failures)."""
    rows = conn.execute("SELECT check_name, is_blocking, failures FROM etl.v_data_quality_checks WHERE failures > 0").fetchall()
    return [(name, bool(blocking), int(failures)) for name, blocking, failures in rows]
