# UK Climate Risk

A small, illustrative catastrophe model for UK windstorm and flood: what a portfolio of properties loses in
an average year, a 1-in-10 year and the 1-in-200 year Solvency II capital is held for, and what the same
weather does to power prices. A sister project to Clean Power 2030, reusing its regions, weather and price
data. It was built to learn the method, so the figures are rough; the sensitivity check shows how rough.

**Live:** https://tristanbowdenfreeman-maker.github.io/tiny-summit/climate-risk/

## What it finds

- Insuring every property in Great Britain (about 29.7 million) against windstorm and river/coastal flood
  costs about £0.7bn in an average year, £1.1bn in a 1-in-10 year and £3.3bn in a 1-in-200 year.
- Flood drives the average, windstorm the tail: £2.8bn on its own in a 1-in-200 year, against £1.0bn
  for flood.
- The 1-in-200 is the least certain figure. Other reasonable choices, each recalibrated, put it anywhere
  from £1.6bn to £8.6bn, and the windstorm calibration matters most. Simulation noise is small by comparison
  (£3.1bn to £3.3bn across ten seeds).
- South West and North East England have the highest risk cost per property, mostly from flood. Scotland,
  South Wales and London have the lowest, though flood there is barely covered (see Limits).
- On the Agile tariff, calm days cost about 11% more than their month's average and the windiest days about
  17% less, so the storm days that drive claims are some of the cheapest for power.

The page's figures come from the data, so they may have moved on from these.

## How it works

1. **Hazard** ([fetch.py](fetch.py))
   - The strongest gust each day since 1979 at one point per region, from Open-Meteo's ERA5 archive.
   - Every flood warning the Environment Agency has issued since 2006.
   - Each flood warning area is placed in a region using NESO's DNO boundaries.
2. **Exposure** ([portfolio.csv](portfolio.csv)): a hypothetical portfolio that insures every property
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
6. **Back-test**: the model is set against five ABI events. February 2020 and 2022 calibrate windstorm and the
   2023 storms fall in the year flood is calibrated on, so only 2015-16 and 2007 are clean tests.
7. **Sensitivity**: the GB figures are rerun with one choice changed at a time, each recalibrated: windstorm
   calibrated on 2020 or 2022 alone, a damage exponent of 2 or 4, and a Pareto tail on 5%, 20% or none of
   the loss days. Ten seeds measure simulation noise, and 30 resamples of the historical years show how much
   the 1-in-200 depends on the 47 years history gave.

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
  many homes it reaches. The model is close on the 2023 storms (0.8×, mostly flood), about 3.5× too low on
  Desmond in 2015-16 (fewer, deeper floods) and about 14× too low on summer 2007 (mostly surface water,
  which warnings don't cover).
- **One gust point per region.** It misses storms whose worst winds stay on the coast, like Ciarán, and sees
  February 2020 as much worse than February 2022, so one scale overstates 2020 (2.0×) and understates 2022
  (0.7×). More ERA5 points per region, from the same API, is the first thing to try.
- **Flood is England only.** None in North Scotland, and only the English edges of South Scotland and the two
  Welsh regions.
- **Losses are as if today.** Every past year runs against today's properties and claim costs, in today's
  climate. A +2°C scenario (UKCP18) is next.
- **Regional 1-in-10 and 1-in-200 are fitted per region**, so they don't add up to the GB figures.
- **Not modelled:** surface water, subsidence, freeze, deductibles and policy limits.
- **The ABI has revised 2023.** Its February 2025 release implies about £458m of home weather claims, against
  the £573m used here from April 2024.

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
