"""A small catastrophe model for UK windstorm and river/coastal flood, and the weather-price link.

The portfolio is made up: every property connected to each DNO region (portfolio.csv), insured.
Each historical year's weather is run against today's portfolio, so losses are "as if that year
happened now", the usual way a cat model treats history.

Windstorm  Klawa & Ulbrich's storm loss index. A day only counts at a region's weather point
           when its strongest gust beats that point's 98th percentile (local buildings are built
           for local wind), and damage grows with the cube of the excess:
               loss = scale x properties x max(0, gust / gust98 - 1)^3
Flood      Each Flood Warning or Severe Flood Warning the Environment Agency issued is one unit of
           loss. England only, from 2006.

Storm is scaled so the two windstorm clusters of February 2020 and February 2022 add up to the
wind part of what the ABI reported for them. Flood is then scaled so the whole of 2023 matches the
ABI's weather claims that year, less burst pipes. The other ABI events in CHECKS are held back as tests.

Frequency x severity: for each region and peril, loss days per year are Poisson, and the loss on a
day is drawn from the days history had, with a generalised Pareto tail fitted to the largest 10%
(so a simulated day can be worse than any on record). 100,000 simulated years give the 1-in-10
and 1-in-200 losses. Writes site/climate-risk/data/*.json.

Run with: python climate_risk/model.py   (after climate_risk/fetch.py)
"""

import json
import sys
from datetime import date
from pathlib import Path

import numpy as np
import pandas as pd
from scipy import stats

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "raw"
OUT = ROOT / "site" / "climate-risk" / "data"
STORM_YEARS = range(1979, 2026)
FLOOD_YEARS = range(2006, 2026)
SIMULATED_YEARS = 100_000
SEED = 2030

WARNING_TYPES = {"flood warning", "severe flood warning"}  # first issues only, not updates, alerts or watches

# ABI figures. "fits" names the peril an event calibrates; the others are fair tests. "abi_wind" is
# the part of a storm event's claims that was wind, which is what storm is scaled to.
CHECKS = [
    # The ABI's first estimate for Ciara and Dennis was £149m wind and £214m flood, so 41% wind.
    {"name": "Storms Ciara, Dennis and Jorge", "start": "2020-02-08", "end": "2020-03-01", "abi": 543e6,
     "abi_wind": 543e6 * 149 / 363, "abi_note": "storm and flood claims", "fits": "storm"},
    # No split published; Franklin's river flooding is small next to Eunice's wind, so all of it.
    {"name": "Storms Dudley, Eunice and Franklin", "start": "2022-02-16", "end": "2022-02-21", "abi": 473e6,
     "abi_wind": 473e6, "abi_note": "property claims", "fits": "storm"},
    {"name": "Storms Babet, Ciarán and Debi", "start": "2023-10-18", "end": "2023-11-14", "abi": 507e6,
     "abi_note": "home and business claims", "fits": None},
    {"name": "Winter floods (Desmond, Eva, Frank)", "start": "2015-12-03", "end": "2016-01-03", "abi": 1.3e9,
     "abi_note": "flood claims", "fits": None},
    {"name": "Summer 2007 floods", "start": "2007-06-15", "end": "2007-07-31", "abi": 3.0e9,
     "abi_note": "all claims", "fits": None},
]
# ABI (14 Apr 2024): weather damage to homes (£573m) and businesses (£443m) in 2023, less the £153m
# of home burst pipes, a peril the model doesn't cover. Flood is calibrated on this.
ABI_2023_WEATHER = 573e6 + 443e6 - 153e6
TAIL_SHARE = 0.10  # the largest 10% of loss days get a fitted generalised Pareto tail
# The EA only covers England: none of North Scotland, and only the English edges of these three.
FLOOD_COVERAGE = {1: "none", 2: "partial", 6: "partial", 7: "partial"}


def load_portfolio() -> pd.DataFrame:
    return pd.read_csv(ROOT / "climate_risk" / "portfolio.csv").set_index("region_id")


def storm_days(portfolio: pd.DataFrame) -> pd.DataFrame:
    """One row per region per day with a damaging gust: the gust, its threshold and the loss, in
    index units until calibrate scales it."""
    gusts = pd.read_parquet(RAW / "climate_risk" / "gusts.parquet")
    gusts["gust98"] = gusts.groupby("region_id").gust_ms.transform(lambda g: g.quantile(0.98))
    excess = np.clip(gusts.gust_ms / gusts.gust98 - 1, 0, None) ** 3
    gusts["loss"] = excess * gusts.region_id.map(portfolio.properties)
    return gusts[gusts.loss > 0]


def flood_days() -> pd.DataFrame:
    """One row per region per day with flood warnings: how many, and the loss (in warnings until
    calibrate scales it)."""
    warnings = pd.read_parquet(RAW / "climate_risk" / "warnings.parquet")
    areas = pd.read_parquet(RAW / "climate_risk" / "flood_areas.parquet")
    warnings = warnings[warnings.type.str.lower().isin(WARNING_TYPES)].copy()
    warnings["region_id"] = warnings.code.map(areas.set_index("code").region_id)
    # Codes retired since 2006 aren't in today's list. The first three characters are the EA team
    # that issued it, so those take the region most of that team's current areas are in.
    by_team = areas.assign(team=areas.code.str[:3]).groupby("team").region_id.agg(lambda r: r.mode()[0])
    missing = warnings.region_id.isna()
    warnings.loc[missing, "region_id"] = warnings.loc[missing, "code"].str[:3].map(by_team)
    warnings = warnings.dropna(subset=["region_id"]).astype({"region_id": int})
    warnings["day"] = warnings.issued.dt.normalize()
    days = warnings.groupby(["region_id", "day"]).size().rename("warnings").reset_index()
    days["loss"] = days.warnings.astype(float)
    return days


def annual(days: pd.DataFrame, years: range, regions) -> pd.DataFrame:
    """Loss by year (rows) and region (columns), zero where nothing happened."""
    table = days.assign(year=days.day.dt.year).pivot_table(index="year", columns="region_id", values="loss", aggfunc="sum")
    return table.reindex(index=list(years), columns=list(regions)).fillna(0)


def window_loss(days: pd.DataFrame, start: str, end: str) -> float:
    return float(days.loc[days.day.between(pd.Timestamp(start), pd.Timestamp(end)), "loss"].sum())


def calibrate(storms: pd.DataFrame, floods: pd.DataFrame) -> dict[str, float]:
    """Scale storm on its ABI events, then flood on what the ABI reported for 2023 beyond the
    model's storm loss, and apply both. Returns £ per index unit (storm) and £ per warning (flood)."""
    events = [c for c in CHECKS if c["fits"] == "storm"]
    storm = sum(c["abi_wind"] for c in events) / sum(window_loss(storms, c["start"], c["end"]) for c in events)
    storms["loss"] *= storm
    in_2023 = lambda days: float(days.loc[days.day.dt.year == 2023, "loss"].sum())  # noqa: E731
    flood = (ABI_2023_WEATHER - in_2023(storms)) / in_2023(floods)
    floods["loss"] *= flood
    return {"storm": storm, "flood": flood}


def frequency_severity(days: pd.DataFrame, years: range) -> dict:
    """Loss days per year, the loss on each of those days, and a generalised Pareto fitted to the
    largest TAIL_SHARE of them, above the threshold."""
    losses = np.sort(days.loc[days.day.dt.year.isin(years)].groupby("day").loss.sum().to_numpy())
    fit = {"per_year": len(losses) / len(years), "losses": losses, "mean": float(losses.mean()) if len(losses) else 0.0}
    if len(losses) >= 20:
        threshold = float(np.quantile(losses, 1 - TAIL_SHARE))
        shape, _, scale = stats.genpareto.fit(losses[losses > threshold] - threshold, floc=0)
        fit.update(threshold=threshold, shape=min(shape, 0.9), scale=scale)  # cap keeps the tail mean finite
    return fit


def simulate(fit: dict, rng: np.random.Generator) -> np.ndarray:
    """SIMULATED_YEARS of annual loss: a Poisson number of loss days, each one resampled from
    history, with days in the top TAIL_SHARE redrawn from the fitted tail."""
    counts = rng.poisson(fit["per_year"], SIMULATED_YEARS)
    if counts.sum() == 0 or not len(fit["losses"]):
        return np.zeros(SIMULATED_YEARS)
    draws = rng.choice(fit["losses"], size=counts.sum())
    if "threshold" in fit:
        tail = draws > fit["threshold"]
        draws[tail] = fit["threshold"] + stats.genpareto.rvs(fit["shape"], scale=fit["scale"], size=tail.sum(), random_state=rng)
    return np.bincount(np.repeat(np.arange(SIMULATED_YEARS), counts), weights=draws, minlength=SIMULATED_YEARS)


def return_level(simulated: np.ndarray, years: float) -> float:
    return float(np.quantile(simulated, 1 - 1 / years))


def price_vs_wind() -> dict:
    """Agile prices against the day's wind. Each day's price is set against its month's average, so
    the 2022 price spike doesn't swamp the comparison."""
    prices = []
    for path in sorted((RAW / "prices").glob("*.json")):
        for part in json.loads(path.read_text())["parts"]:
            for slots in part["regions"].values():
                prices += [(s["from"], s["p"]) for s in slots]
    prices = pd.DataFrame(prices, columns=["at", "p"])
    prices["day"] = pd.to_datetime(prices["at"], utc=True).dt.tz_convert("Europe/London").dt.tz_localize(None).dt.normalize()
    daily = prices.groupby("day").p.mean().rename("price").to_frame()

    wind = []
    for path in sorted((RAW / "weather").glob("*.json")):
        for location in json.loads(path.read_text()):
            hourly = location["hourly"]
            wind += list(zip(hourly["time"], hourly["wind_speed_100m"]))
    wind = pd.DataFrame(wind, columns=["at", "wind"]).dropna()
    wind["day"] = pd.to_datetime(wind["at"]).dt.normalize()
    daily = daily.join(wind.groupby("day").wind.mean(), how="inner")

    gusts = pd.read_parquet(RAW / "climate_risk" / "gusts.parquet")
    gust98 = gusts.groupby("region_id").gust_ms.transform(lambda g: g.quantile(0.98))
    damaging = gusts[gusts.gust_ms > gust98].groupby("day").size()
    daily["storm"] = daily.index.map(damaging).fillna(0) >= 3  # damaging gusts in 3+ regions

    daily["month"] = daily.index.to_period("M")
    daily["relative"] = daily.price / daily.groupby("month").price.transform("mean") - 1
    daily["decile"] = pd.qcut(daily.wind, 10, labels=False) + 1
    deciles = daily.groupby("decile").agg(wind=("wind", "mean"), relative=("relative", "mean"), price=("price", "mean"), days=("price", "size"))
    calm, windy = daily[daily.decile == 1], daily[daily.decile == 10]
    return {
        "from": daily.index.min().date().isoformat(),
        "to": daily.index.max().date().isoformat(),
        "days": int(len(daily)),
        "deciles": [
            {"decile": int(d), "wind_ms": round(r.wind, 1), "vs_month_pct": round(100 * r.relative, 1),
             "price_p": round(r.price, 1), "days": int(r.days)}
            for d, r in deciles.iterrows()
        ],
        "calm_vs_month_pct": round(100 * calm.relative.mean(), 1),
        "windy_vs_month_pct": round(100 * windy.relative.mean(), 1),
        "storm_days": int(daily.storm.sum()),
        "storm_vs_month_pct": round(100 * daily[daily.storm].relative.mean(), 1),
        "calm_minus_windy_p": round(calm.price.mean() - windy.price.mean(), 1),
    }


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(SEED)
    portfolio = load_portfolio()
    regions = portfolio.index
    storms, floods = storm_days(portfolio), flood_days()
    scales = calibrate(storms, floods)
    storm_years, flood_years = annual(storms, STORM_YEARS, regions), annual(floods, FLOOD_YEARS, regions)

    region_rows = []
    for region_id, row in portfolio.iterrows():
        storm_fit = frequency_severity(storms[storms.region_id == region_id], STORM_YEARS)
        flood_fit = frequency_severity(floods[floods.region_id == region_id], FLOOD_YEARS)
        total = simulate(storm_fit, rng) + simulate(flood_fit, rng)
        storm_eal, flood_eal = float(storm_years[region_id].mean()), float(flood_years[region_id].mean())
        region_rows.append({
            "region_id": int(region_id), "region": row.region, "properties": int(row.properties),
            "storm_eal": round(storm_eal), "flood_eal": round(flood_eal), "eal": round(storm_eal + flood_eal),
            "rp10": round(return_level(total, 10)), "rp200": round(return_level(total, 200)),
            "storm_days_per_year": round(storm_fit["per_year"], 1), "storm_loss_per_day": round(storm_fit["mean"]),
            "flood_days_per_year": round(flood_fit["per_year"], 1), "flood_loss_per_day": round(flood_fit["mean"]),
            "risk_cost_per_property": round((storm_eal + flood_eal) / row.properties, 2),
            "flood_coverage": FLOOD_COVERAGE.get(int(region_id), "full"),
        })

    # GB: fit each peril's national loss days, so one storm or flood hits many regions at once.
    gb_storm_sim = simulate(frequency_severity(storms, STORM_YEARS), rng)
    gb_flood_sim = simulate(frequency_severity(floods, FLOOD_YEARS), rng)
    gb_total = gb_storm_sim + gb_flood_sim
    gb_storm, gb_flood = storm_years.sum(axis=1), flood_years.sum(axis=1)
    history = pd.DataFrame({"storm": gb_storm, "flood": gb_flood.reindex(gb_storm.index)})
    worst_storm = storms.groupby("day").loss.sum().nlargest(5)
    gb = {
        "properties": int(portfolio.properties.sum()),
        "storm_eal": round(float(gb_storm.mean())), "flood_eal": round(float(gb_flood.mean())),
        "eal": round(float(gb_storm.mean() + gb_flood.mean())),
        "simulated_eal": round(float(gb_total.mean())),
        "rp10": round(return_level(gb_total, 10)), "rp200": round(return_level(gb_total, 200)),
        "storm_rp200": round(return_level(gb_storm_sim, 200)), "flood_rp200": round(return_level(gb_flood_sim, 200)),
        "curve": [{"years": y, "total": round(return_level(gb_total, y)), "storm": round(return_level(gb_storm_sim, y)),
                   "flood": round(return_level(gb_flood_sim, y))} for y in (2, 5, 10, 20, 50, 100, 200, 500)],
        "history": [{"year": int(y), "storm": round(r.storm), "flood": None if pd.isna(r.flood) else round(r.flood)}
                    for y, r in history.iterrows()],
        "worst_storm_days": [{"day": d.date().isoformat(), "loss": round(v)} for d, v in worst_storm.items()],
        "model_2023": round(float(gb_storm[2023] + gb_flood[2023])), "abi_2023": ABI_2023_WEATHER,
        "storm_scale_per_property": round(scales["storm"]), "flood_scale_per_warning": round(scales["flood"]),
    }

    checks = []
    for check in CHECKS:
        storm, flood = window_loss(storms, check["start"], check["end"]), window_loss(floods, check["start"], check["end"])
        checks.append({**check, "model_storm": round(storm), "model_flood": round(flood), "model": round(storm + flood),
                       "ratio": round((storm + flood) / check["abi"], 2)})

    meta = {
        "built": date.today().isoformat(),
        "storm_years": [STORM_YEARS.start, STORM_YEARS.stop - 1],
        "flood_years": [FLOOD_YEARS.start, FLOOD_YEARS.stop - 1],
        "simulated_years": SIMULATED_YEARS,
    }
    for name, payload in {"regions": region_rows, "gb": gb, "checks": checks, "prices": price_vs_wind(), "meta": meta}.items():
        (OUT / f"{name}.json").write_text(json.dumps(payload, indent=1, ensure_ascii=False))
    print(json.dumps({"gb": {k: v for k, v in gb.items() if not isinstance(v, list)}, "checks": [
        {k: c[k] for k in ("name", "abi", "model_storm", "model_flood", "ratio")} for c in checks]}, indent=1, ensure_ascii=False))


if __name__ == "__main__":
    main()
