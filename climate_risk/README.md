# UK Climate Risk

A small catastrophe model for UK windstorm and flood. I built it to show how an insurer sizes weather
risk: how much a portfolio of properties loses in an average year, in a 1-in-10 year and in the 1-in-200
year that Solvency II capital is held for. It also shows what the same weather does to power prices. It's
a sister project to Clean Power 2030 and reuses its regions, weather and price data.

**Live:** https://tristanbowdenfreeman-maker.github.io/tiny-summit/climate-risk/

## What it finds

- Insuring every property in Great Britain (about 29.7 million) against windstorm and river/coastal flood
  costs about £0.7bn in an average year, £1.1bn in a 1-in-10 year and £3.2bn in a 1-in-200 year.
- Flood drives the average and windstorm drives the tail. Flood happens most years, while windstorm on its
  own reaches £2.7bn in a 1-in-200 year, against £1.0bn for flood.
- South West and North East England have the highest risk cost per property, mostly from flood. Scotland,
  South Wales and London have the lowest, though flood in Scotland and Wales is barely covered (see below).
- Calm days cost about 11% more than their month's average on the Agile tariff, and the windiest days
  about 17% less. The storm days that drive claims are some of the cheapest days for power.

The page's figures come from the data, so they may have moved on from these.

## How it works

1. **Hazard** ([fetch.py](fetch.py))
   - The strongest gust each day since 1979 at one point per region, from Open-Meteo's ERA5 archive.
   - Every flood warning the Environment Agency has issued since 2006.
   - Each flood warning area is placed in a region using NESO's DNO boundaries.
2. **Exposure** ([portfolio.csv](portfolio.csv)): a made-up portfolio that insures every property
   connected in each of the 14 electricity regions. The counts are rounded DNO customer numbers.
3. **Vulnerability** ([model.py](model.py))
   - Windstorm follows Klawa & Ulbrich (2003). Only gusts above a place's own 98th percentile do damage,
     and loss grows with the cube of the excess.
   - Each flood warning is a fixed loss.
4. **Calibration**
   - Windstorm is scaled to the wind part of the ABI's figures for the February 2020 and February 2022
     storm clusters. The ABI split 2020 as 41% wind and 59% flood; 2022 has no split and counts as all wind.
   - Flood is then scaled so 2023 matches the ABI's weather claims for that year, less the £153m of burst
     pipes the model doesn't cover (£863m).
5. **Simulation**
   - Frequency × severity for each region and peril: a Poisson number of loss days a year.
   - Each day's loss is resampled from history, with a generalised Pareto tail on the largest 10%.
   - This runs for 100,000 years.
6. **Checks**: the model is set against five ABI events, three of which it wasn't calibrated on.

```bash
python climate_risk/fetch.py
```

```bash
python climate_risk/model.py
```

The model writes `site/climate-risk/data/*.json`. Install its extra packages from
[requirements.txt](requirements.txt) (kept apart from the Azure pipeline's). The price comparison
reads the Agile and weather files Clean Power 2030's pipeline caches in `raw/`.

## Limits

- **The flood proxy is the weak point.** A warning says where water is expected, not how deep it is or how
  many homes it reaches.
  - The model gets the 2023 storms roughly right (0.8×), mostly through flood.
  - It's about 3.5× too low for Desmond in 2015-16, when record river levels flooded fewer, deeper areas.
  - It's about 14× too low for summer 2007, which was mostly surface water, and flood warnings don't cover
    surface water.
- **Windstorm uses one gust point per region**, so it misses storms whose worst winds stay on the coast,
  like Ciarán in 2023. It also sees February 2020's gusts as much worse than February 2022's, so one scale
  can't fit both: it overstates 2020 (2.0×) and understates 2022 (0.7×). More ERA5 points per region, from
  the same API, is the first thing to try.
- **Flood is England only.** It covers no flood in North Scotland, and only the English edges of South
  Scotland and the two Welsh regions.
- **Losses are as if today**: every past year is run against today's properties and claim costs. Climate
  change isn't in it yet; a +2°C scenario (UKCP18) is the next step.
- **Regional 1-in-10 and 1-in-200 are fitted region by region**, so they don't add up to the GB figures.
- **Not modelled:** surface water, subsidence, freeze, deductibles and policy limits.
- **The ABI has revised its 2023 figure.** Its February 2025 release implies 2023 home weather claims of about
  £458m, against the £573m used here from its April 2024 release.

## Sources

- **ABI loss figures.** The ABI's news pages before 2024 are offline, so most of these link to trade-press
  reports of its releases.
  - 2023 weather claims (homes £573m, of which £153m burst pipes; businesses £443m): [ABI, April 2024](https://www.abi.org.uk/media-hub/news-post/weather-damage-insurance-claims-worst-on-record)
  - February 2020 storms (£543m storm and flood): [Claims Media, April 2022](https://claimsmag.co.uk/2022/04/abi-expects-insurers-to-pay-out-almost-500m-to-meet-february-storm-claims/);
    the wind and flood split (£149m and £214m) is the ABI's first estimate, via [ITV, March 2020](https://www.itv.com/news/2020-03-07/insurance-payouts-for-storms-dennis-and-ciara-set-to-top-360m)
  - February 2022 storms (£473m property, out of £497m): [Reinsurance News](https://www.reinsurancene.ws/insurers-to-pay-out-nearly-500m-on-storms-dudley-eunice-franklin-abi/)
  - Babet, Ciarán and Debi (£507m homes and businesses, out of £560m with vehicles): [Commercial Risk](https://www.commercialriskonline.com/uk-storm-trio-caused-560m-in-damage/)
  - 2015-16 floods: [Insurance Times](https://www.insurancetimes.co.uk/abi-uk-floods-to-cost-insurers-13bn/1416942.article)
  - Summer 2007 floods: the Environment Agency's [Review of 2007 summer floods](https://assets.publishing.service.gov.uk/media/5a7c9a55ed915d6969f460bd/geho1107bnmi-e-e.pdf)
    puts insured losses at "approaching £3 billion".
- **Capital standard:** the 1-in-200 is the 99.5% one-year Solvency Capital Requirement (Solvency II Article 101,
  carried into the PRA Rulebook). The PRA's expectations on climate risk are in SS5/25, *Enhancing banks' and
  insurers' approaches to managing climate-related risks* (December 2025), which replaced SS3/19.
- **Flood warnings:** [Environment Agency Historic Flood Warnings](https://www.data.gov.uk/dataset/d4fb2591-f4dd-4e7f-9aaf-49af94437b36/historic-flood-warnings2) (OGL v3)
- **Gusts:** [Open-Meteo historical archive](https://open-meteo.com/en/docs/historical-weather-api) (ERA5, CC BY 4.0)
- **Region boundaries:** [NESO GB DNO licence areas](https://www.neso.energy/data-portal/gis-boundaries-gb-dno-license-areas)
