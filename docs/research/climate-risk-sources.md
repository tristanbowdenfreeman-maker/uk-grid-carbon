# Climate risk model: are the sources the best open ones?

Checked 27 October 2026 against `climate_risk/README.md`, `model.py` and `fetch.py`. Primary sources are linked where I could reach them; anything I only found second-hand is marked **(secondary)**.

## Summary

**Keep:** Klawa & Ulbrich as the storm loss function, ERA5 as the gust source, the EA flood warning archive as a frequency signal, NESO DNO boundaries, and the Solvency II 1-in-200 framing.

**Swap or fix, ranked by value for effort:**

1. **Fix the calibration targets (small).** Two of them are inconsistent with what the ABI says it measured:
   - February 2020 (£543m) is "storm *and flood* claims". The ABI's first estimate for Ciara and Dennis was £214m flood and £149m wind. The model scales *storm only* to it, then adds model flood on top. That is the likely cause of the 2.58× overstatement.
   - The 2023 target (£1,016m) includes £153m of burst pipes (freeze), which the model doesn't cover. The ABI's February 2025 release also implies a different 2023 home figure (about £458m, against £573m).
2. **Cite ABI figures from the ABI (small).** Every figure the README cites is second-hand. ABI primary pages exist for 2023 and 2024. For the others, the older ABI news URLs now return 404, so the best available is trade press quoting the release.
3. **Add a flood *exposure* layer from EA "Risk of Flooding from Rivers and Sea – Postcodes in Areas at Risk" (small to medium).** It gives property counts by risk band per postcode, so flood loss can be spread by how many properties are actually at risk, not by how many warnings were issued. Use SEPA and NRW flood maps (both OGL) for Scotland and Wales.
4. **Use more ERA5 points per region (small).** Use the same Open-Meteo call with 10–30 population-weighted grid points per region, including coastal cells. This targets the Ciarán miss directly.
5. **Validate against C3S windstorm footprints (medium).** "Windstorm tracks and footprints derived from reanalysis over Europe between 1940 to present" is ERA5-based, CC-BY, and has footprints per storm. It needs a free CDS account, which breaks the "no key" rule in `fetch.py`.
6. **Use dwelling counts for exposure instead of DNO customers (medium).** Use VOA Council Tax stock of properties (England and Wales) plus Scottish dwelling estimates, and add ABI average claim figures as the severity anchor.
7. **v2 climate scenario (medium):**
   - Flood: EA peak river flow allowances, based on UKCP18.
   - Wind: UKCP18 storms factsheet. The signal is weak and uncertain, so say so.
   - Cross-check: CBES 2021 general insurance results (UK AAL +~50% under No Additional Action).
8. **Reference the regulatory frame (small):** PRA SS5/25 (it replaced SS3/19 on 3 Dec 2025), the Solvency II Art. 101 / PRA Rulebook 99.5% one-year SCR, and Lloyd's RDS.

## 1. ABI loss figures

| Event | Model uses | What the ABI said | Primary? | Verdict |
|---|---|---|---|---|
| Ciara, Dennis, Jorge (Feb 2020) | £543m, "storm and flood claims, including motor", **fits storm** | First estimate (≈7 Mar 2020, Ciara and Dennis only): **£363m** = £214m flood + £149m wind, about 82,000 claims, including about 7,100 motor claims (≈£33m). The £543m for all three storms first appears as a comparison in the ABI's April 2022 release: "an estimated £543 million paid in storm and flood claims". | Secondary ([ITV, 7 Mar 2020](https://www.itv.com/news/2020-03-07/insurance-payouts-for-storms-dennis-and-ciara-set-to-top-360m); [Verisk citing ABI split](https://www.verisk.com/en-gb/blog/storms-ciara-dennis-and-jorge-reinforce-need-for-robust-models); [Claims Media, Apr 2022](https://claimsmag.co.uk/2022/04/abi-expects-insurers-to-pay-out-almost-500m-to-meet-february-storm-claims/)). The ABI's 2020 URL (`abi.org.uk/news/news-articles/2020/03/...`) now 404s. | The number is fine. The use is wrong: the figure is mostly flood, so calibrate it on storm + flood together, or take only the wind share (≈41% on the March 2020 split, ≈£220m) for storm. I could not confirm "including motor" for the £543m. |
| Dudley, Eunice, Franklin (Feb 2022) | £473m, "property claims", fits storm | ABI, 29 Apr 2022: total **£497m** from 177,000 claims. Of that, **£473m** is property (169,500 claims), about £23m is motor (≈7,500 claims), plus £13m emergency payments and £2.2m alternative accommodation. Franklin brought river flooding (Severn), so part of the £473m is flood. | Secondary ([Claims Media](https://claimsmag.co.uk/2022/04/abi-expects-insurers-to-pay-out-almost-500m-to-meet-february-storm-claims/), [Insurance Age](https://www.insuranceage.co.uk/insight/7946906/abi-puts-february-storm-payouts-at-ps500m), [Reinsurance News](https://www.reinsurancene.ws/insurers-to-pay-out-nearly-500m-on-storms-dudley-eunice-franklin-abi/)) | Confirmed. The flood share is unknown. |
| Babet, Ciarán, Debi (Oct–Nov 2023) | £507m, "home and business claims" | ABI, Dec 2023: total **£560m** = £352m homes + £155m business + £53m vehicles, from 48,700 claims. £352m + £155m = **£507m**. | Secondary ([Yahoo/PA](https://malaysia.news.yahoo.com/insurers-expect-pay-560m-cover-000100499.html), [Commercial Risk, 14 Dec 2023](https://www.commercialriskonline.com/uk-storm-trio-caused-560m-in-damage/)) | Confirmed: £507m is property excluding motor. The README should say the headline was £560m. |
| Winter floods 2015-16 (Desmond, Eva, Frank) | £1.3bn, "flood claims" | ABI, Jan 2016: **≈£1.3bn**, covering about 3 Dec 2015 – 3 Jan 2016. About 15,000–16,000 property claims (5,000+ business) plus 5,600 motor claims. Average domestic flood claim about £50,000. PERILS put the property market loss at about £1.24bn. | Secondary ([Insurance Times](https://www.insurancetimes.co.uk/abi-uk-floods-to-cost-insurers-13bn/1416942.article), [City AM](https://cityam.com/?p=312843), [Insurance Post](https://postonline.co.uk/post/news/2459246/abi-85-of-claims-from-floods-caused-by-storms-desmond-eva-and-frank-paid-out), [PERILS via Intelligent Insurer](https://www.intelligentinsurer.com/news/perils-reveals-second-uk-floods-estimate-8151)) | Confirmed as an early estimate that probably includes motor. The model's window matches. |
| Summer 2007 floods | £3.0bn, "all claims" | There is no ABI page I could reach. Government primary: the EA's *Review of 2007 summer floods* (Dec 2007) says "insured losses are approaching £3 billion". A summary of the Pitt Review (June 2008) gives about **180,000 claims and roughly £3bn**. The ABI was quoted at the time as "approximately £3bn" paid, with July alone at £2.5bn. | Partly primary ([EA review, gov.uk](https://assets.publishing.service.gov.uk/media/5a7c9a55ed915d6969f460bd/geho1107bnmi-e-e.pdf), quoted from search; the PDF didn't render here). Otherwise secondary ([CII summary of Pitt](https://media.umbraco.io/ciigroup-dxp/wmbejxjo/cii_pitt_review.pdf), [Insurance Age](https://www.insuranceage.co.uk/node/1191676)). | Cite the EA review, and Pitt for the claim count, rather than "widely quoted". The figure covers homes, businesses and vehicles across June and July. |
| 2023 weather claims | £1,016m = £573m homes + £443m business | ABI, 14 Apr 2024 (**primary**): home weather claims **£573m**, a record and +36% on 2022's £421m. That splits into **£286m flood, £133m storm and £153m burst pipes**. Business weather claims were **£443m**, not split. Average weather home claim £4,916. Motor is not included. | **Primary:** [ABI](https://www.abi.org.uk/media-hub/news-post/weather-damage-insurance-claims-worst-on-record) | Two problems. (a) The £153m freeze is not a modelled peril, so the target should be about £863m, less any freeze in the business figure. (b) The ABI's own [release of 10 Feb 2025](https://www.abi.org.uk/news/news-articles/2025/2/more-action-needed-to-protect-properties-as-adverse-weather-takes-record-toll-on-insurance-claims-in-2024/) says 2024 home weather (£585m) was £127m above 2023 and £77m above a 2022 record. That implies 2023 ≈ £458m and 2022 ≈ £508m, so the series has been revised or redefined. State the vintage you use. |

The ABI's quarterly figures come from its Property Insurance Premium and Claims Tracker (about 28m policies, data since 2017, per the Feb 2025 release). That is the right series to cite for annual totals.

## 2. Flood hazard and loss sources

The EA warning count is a frequency signal: it says where and when floods happened. It carries no information about severity, which is why 2015-16 (deep, concentrated) and 2007 (surface water) come out low. The sources below add severity or exposure.

| Source | What it gives | Coverage | Licence | Fit for a 2-day static build |
|---|---|---|---|---|
| [EA Risk of Flooding from Rivers and Sea – Postcodes in Areas at Risk](https://www.data.gov.uk/dataset/5a98b0a1-2741-4b2f-a51b-5b42f13219f2/risk-of-flooding-from-rivers-and-sea-postcodes-in-areas-at-risk2) | Property counts per postcode by likelihood band (high, medium, low, very low) and property type. There is a 2026 revision, which probably reflects NaFRA2 (not confirmed). | England | EA open data with OS and Royal Mail attribution; confirm OGL on the download page | **Best value.** Map postcodes to DNO regions, then weight each region's flood severity by properties in the high and medium bands. A few hours of work. |
| [NaFRA2 national assessment, Dec 2024](https://www.preventionweb.net/publication/national-assessment-flood-and-coastal-erosion-risk-england-2024) (EA) | Headline: about 6.3m properties in England at risk from rivers, sea or surface water, rising to about 8m by mid-century. New RoFRS and surface-water maps were [released 28 Jan 2025](https://environmentagency.blog.gov.uk/2025/01/28/enhancing-flood-and-coastal-erosion-risk-digital-services-with-the-latest-data-and-mapping). | England | OGL (EA) | Good for headline checks and for a surface-water exposure layer. The full rasters are large; use the postcode summaries instead. |
| [EA Recorded Flood Outlines](https://ckan.publishing.service.gov.uk/dataset/recorded-flood-outlines1) and Historic Flood Map | Polygons of observed floods since 1946, from rivers, sea, groundwater and surface water, with dates and source | England | EA; licence not confirmed in what I read | Medium effort. Intersecting the 2007 and 2015 outlines with property points would give an event footprint, which is good for validation. Coverage is patchy: "no outline" does not mean "never flooded". |
| [SEPA flood maps](https://www.sepa.org.uk/environment/environmental-data/) (river, coastal, surface water) | Hazard extents by likelihood | Scotland | OGL v3, plus OS terms ([terms](https://map.sepa.org.uk/floodmaps/FloodRisk/ViewTerms)) | Fills the North Scotland gap for exposure. SEPA has no historic warning archive equivalent that I found. |
| [NRW Flood Risk Assessment Wales](https://datamap.gov.wales/layergroups/inspire-nrw:FloodRiskAssessmentWales) | Risk bands for rivers, sea, and surface water and small watercourses | Wales | OGL (DataMap Wales) | Same as SEPA. GeoPackage download. |
| Flood Re [Annual Report 2024/25](https://assets.publishing.service.gov.uk/media/685e77d162b2e559cbd7534c/flood-re-ara-2024-25.pdf) | 346,200 policies ceded and £159.6m claims paid in 2024/25. Gross claims of £241.6m in 2023/24 per Insurance Age (secondary). | UK high-risk homes | Crown/published report | Useful as a cross-check on high-risk exposure and flood claims. Not a hazard source. |
| [EA flood warning archive](https://www.data.gov.uk/dataset/d4fb2591-f4dd-4e7f-9aaf-49af94437b36/historic-flood-warnings2) (current) | Event dates and areas, 2006 onward | England | OGL v3 | Keep for timing and frequency. |

Surface water: NaFRA2 includes it, and a secondary source says it is the largest of the three sources by property count. None of the open sources gives historic surface-water event losses, so 2007 will stay an underestimate unless surface water is added as a separate exposure-weighted peril.

## 3. Windstorm sources

- **ERA5 is the right base.** Open-Meteo serves the 0.25° ERA5 grid, so the same API can return many points per region at no extra cost. The cheapest fix for Ciarán, which was coastal (Cornwall and Channel coast), is to sample 10–30 points per region, weighted by population or properties, including coastal cells. The Klawa & Ulbrich per-point 98th percentile already corrects for local gust bias. An [Energy Reports (2023) evaluation](https://doaj.org/article/c2d7c314ea3f47d591acc7568e6b6f4c) of ERA5 against 205 UK stations found the largest errors at coastal and mountain sites (mean wind, not gusts).
- **[C3S "Windstorm tracks and footprints… 1940 to present"](https://cds.climate.copernicus.eu/datasets/sis-european-wind-storm-reanalysis)** is the best open upgrade:
  - ERA5 maximum 10 m gust over 72 h per storm, on the 0.25° grid and a downscaled 0.016° grid.
  - Landfalling storms only; NetCDF footprints, CSV tracks, SSI indices.
  - CC-BY, v1.0 published June 2025, updated monthly. Needs a free CDS account and API key.
  - Medium effort: it gives a storm-event (not daily) loss table.
  - The older companion is [Winter windstorm indicators 1979–2021](https://cds.climate.copernicus.eu/datasets/sis-european-wind-storm-indicators) (CC-BY/ODbL), which includes loss indicators and a synthetic event set.
- **[XWS catalogue](https://nhess.copernicus.org/articles/14/2487/2014/)** (Roberts et al. 2014, NHESS 14:2487, CC BY 3.0): 50 extreme storms from 1979–2012 with 3-s gust footprints. It ends in 2012, so it's useful only for validating the historic storms (Daria/Burns' Day 1990, the 1987 storm, Kyrill).
- **[MIDAS Open](https://catalogue.ceda.ac.uk/uuid/91cb9985a6c2453d99084bde4ff5f314/)** (Met Office station hourly maximum gust, OGL, free CEDA login) is the best observed check of ERA5 on named-storm days.
- **HadUK-Grid** has no daily gust variable, so it doesn't fit.
- **EURO-CORDEX** is for v2 only and is a large task.
- **Met Office named-storm pages** ([2021/22 season](https://weather.metoffice.gov.uk/warnings-and-advice/uk-storm-centre/uk-storm-season-2021-22)) are the primary source for observed peak gusts per storm, for example Eunice's 122 mph at the Needles. Cite them in the validation table.

## 4. Exposure

- **DNO customer counts** mix domestic and non-domestic connections. They are a reasonable proxy for property count but not a standard insurance exposure.
- **[VOA Council Tax: stock of properties 2025](https://www.gov.uk/government/statistics/council-tax-stock-of-properties-2025):** 27.2m dwellings in England and Wales at 31 Mar 2025, with tables by region and billing authority. OGL. This is the primary dwelling count to use. Map local authorities to DNO regions by centroid or by population share.
- **[MHCLG dwelling stock live tables](https://www.gov.uk/government/statistical-data-sets/live-tables-on-dwelling-stock-including-vacants)** (Table 109 by region): 25.6m dwellings in England at 31 Mar 2024, provisional. Scotland's figures are from National Records of Scotland / Scottish Government; I didn't retrieve the number.
- **Commercial:** the VOA non-domestic rating list. I didn't check it; it's medium effort.
- **Severity anchor:** ABI average weather home claim £4,916 (2023, primary, link above) and average domestic flood claim about £50,000 (2015-16, secondary). Use these to sanity-check "£ per property per damaging event" rather than to set a sum insured. Open rebuild-cost data (BCIS) is paid, so I found no open sum-insured source.
- **Insured share:** the ABI tracker covers about 28m policies (Feb 2025 release), which supports "most dwellings insured". Flood Re's eligibility rule (homes built before 2009) matters only for a high-risk flood sub-portfolio.

## 5. Vulnerability

- **[Klawa & Ulbrich (2003)](https://nhess.copernicus.org/articles/3/725/2003/)** (NHESS 3:725; cubic excess over the 98th percentile, population-weighted, r = 0.96 for German annual losses) is still the standard simple storm loss index. [Pinto et al. (2012, Clim. Res. 54:1)](https://int-res.com/abstracts/cr/v54/n1/p1-20) used it for future European storm losses.
- **[Prahl et al. (2015, NHESS 15:769)](https://nhess.copernicus.org/articles/15/769/2015/)** compared four damage functions. They found K&U should be "restricted to extreme loss", where it has the least bias. For moderate losses they prefer the probabilistic Prahl et al. (2012) or Heneka et al. (2006) functions. This supports using K&U for the 1-in-200 tail; say in the README that it is weaker for frequent small-loss days.
- **Fixed loss per flood warning:** defensible only as a frequency-times-mean-severity proxy, and the 2015-16 and 2007 checks show it fails on severity.
- **Depth-damage options:**
  - The **Multi-Coloured Manual** (FHRC, Middlesex) is the UK standard, but its data needs a paid licence from [MCM-Online](https://mdx.ac.uk/research/research-centres-and-groups/flood-hazard-research-centre-fhrc). It is not openly usable.
  - The open alternative is the **[JRC global depth-damage functions](https://publications.jrc.ec.europa.eu/repository/handle/JRC105688)** (Huizinga et al. 2017): Europe residential curves plus UK maximum damage values, free download. Its licence is not confirmed; one mirror says CC BY 4.0.
  - Neither helps without depth data. For this build, a cheaper and more honest option is to split severity by NaFRA2 risk band and calibrate each band's loss to the ABI average flood claim.

## 6. v2 +2°C scenario

- **Flood (river):** the EA's [peak river flow climate change allowances](https://www.data.gov.uk/dataset/climate-change-allowances-peak-river-flow-by-management-catchment), by management catchment, with central / higher central / upper end percentiles for the 2020s, 2050s and 2080s. They are derived from UKCP18, OGL, and directly usable as a severity uplift. Wales has its own guidance.
- **Windstorm:**
  - UKCP18's [wind factsheet](https://www.metoffice.gov.uk/binaries/content/assets/metofficegovuk/pdf/research/ukcp/ukcp18-fact-sheet-wind_march21.pdf) finds a modest winter increase in the second half of the century, "modest compared to interannual variability".
  - The 2023 [storms factsheet](https://www.metoffice.gov.uk/binaries/content/assets/metofficegovuk/pdf/research/ukcp/ukcp18-factsheet-storms.pdf) says models disagree, some showing decreases, and that there are no compelling trends in UK gust observations.
  - So run a sensitivity, not a central uplift.
  - Pinto et al. (2012) give about +65% on maximum Western European storm losses by 2060–2100 under high emissions (via secondary summary). That is an upper bound, not a +2°C figure.
- **Framing:**
  - [CCRA4 Independent Assessment Technical Report](https://www.ukclimaterisk.org/publications/technical-report-ccra4-ia/) (Met Office / CCC, May 2026) is the current UK evidence base and replaces CCRA3 (2021) as the citation. I didn't read the flooding chapter.
  - [CBES 2021 results](https://www.bankofengland.co.uk/stress-testing/2022/results-of-the-2021-climate-biennial-exploratory-scenario) (BoE, 24 May 2022), No Additional Action scenario (3.3°C by scenario end): UK general insurers projected about **+50% AAL**. Bank staff analysis suggested increases "as much four times higher". That makes it a good anchor for the "how big could the uplift be" paragraph.
  - NGFS scenarios are an alternative if the page needs transition risk. I didn't check them.

## 7. References a UK insurance hiring manager would expect

- **PRA SS5/25** *Enhancing banks' and insurers' approaches to managing climate-related risks*: published with PS25/25 in Dec 2025, effective 3 Dec 2025, **replaces SS3/19** ([Milliman summary](https://www.milliman.com/de-DE/insight/ss-5-25-banks-insurers-climate-risks), secondary; cite the PRA page directly). Citing SS3/19 alone would now look dated.
- **The 1-in-200 definition:** Solvency II Directive 2009/138/EC [Art. 101(3)](https://www.eiopa.europa.eu/rulebook/solvency-ii/article-2188_en), "Value-at-Risk… confidence level of 99.5% over a one-year period". The UK equivalent is in the PRA Rulebook Solvency Capital Requirement – General Provisions (rule number not confirmed). Note that the model's 1-in-200 is an *annual aggregate* loss, consistent with this definition. Say so explicitly, and contrast it with the per-event (occurrence) 1-in-200.
- **[Lloyd's Realistic Disaster Scenarios](https://www.lloyds.com/rds):** the compulsory European windstorm scenario (industry loss €24bn in the 2021 spec). I couldn't read the 2025/2026 PDFs here.
- **PERILS industry loss estimates** for UK storms, for example Éowyn final €765m ([PERILS](https://www.perils.org/news/eur-765m-perils-releases-final-industry-loss-footprint-for-windstorm-eowyn-of-january-2025)). These are a second, independent validation series to the ABI.
- **Flood Re** (above), and the 2039 transition to risk-reflective pricing. This is a natural link to the "risk cost per property" output.
- **CCRA4-IA and CBES** (section 6).

## Recommended source changes

| Current | Recommended | Why | Licence | Effort |
|---|---|---|---|---|
| ABI figures via Reinsurance News / Insurance Times / LBC | ABI primary pages where they exist (2023, 2024); otherwise the earliest trade report quoting the release, labelled secondary | Traceability | n/a | Small |
| Feb 2020 £543m used as a storm-only target | Calibrate storm + flood jointly on Feb 2020, or take the wind share (≈41% per the ABI's March 2020 split) | The ABI figure is mostly flood; this is the likely cause of the 2.58× overstatement | n/a | Small |
| 2023 target £1,016m | £1,016m minus £153m freeze (homes), labelled with the April 2024 vintage; note the Feb 2025 revision | Freeze isn't modelled; ABI series revised | n/a | Small |
| Summer 2007 "untraced £3bn" | EA *Review of 2007 summer floods* (Dec 2007) "approaching £3 billion"; Pitt Review (2008) about 180,000 claims | Government primary source exists | Crown/OGL | Small |
| One ERA5 point per region | 10–30 ERA5 grid points per region (same Open-Meteo API), property-weighted | Catches coastal storms (Ciarán) | CC BY 4.0 | Small |
| None (wind validation) | C3S windstorm footprints 1940–present, plus Met Office storm pages and MIDAS Open for observed gusts | Event footprints and observed checks | CC-BY / OGL | Medium |
| Fixed loss per warning, England only | Warnings for timing, × properties in the high/medium RoFRS bands per region (EA postcode summary), plus SEPA and NRW maps for Scotland and Wales | Adds severity and exposure; closes the Scotland/Wales gap for exposure | OGL (confirm EA postcode file) | Medium |
| No surface water | NaFRA2 surface-water risk counts as a separate exposure-weighted peril, calibrated loosely to 2007 | 2007 is mostly surface water | OGL | Medium |
| DNO customer counts | VOA CTSOP 2025 dwellings (E&W) plus Scottish dwelling estimates, mapped to DNO regions | Standard, citable dwelling stock | OGL | Medium |
| No severity anchor | ABI average weather home claim (£4,916, 2023) and average flood claim (≈£50k, 2015-16) | Sanity check on £ per property | n/a | Small |
| "UKCP18" for +2°C | EA peak river flow allowances (flood); UKCP18 storms factsheet as a sensitivity (wind); CBES 2021 +50% AAL and CCRA4-IA as framing | Usable numbers, current evidence | OGL / Crown | Medium |
| No regulatory references | PRA SS5/25, Solvency II Art. 101 / PRA Rulebook SCR, Lloyd's RDS, PERILS | Expected context for the target roles | n/a | Small |

## Could not verify

- The ABI's own pages for Feb 2020 (£543m), Feb 2022 (£497m / £473m), Babet–Ciarán–Debi (£560m) and 2015-16 (£1.3bn). The old `abi.org.uk/news/news-articles/...` URLs 404 or redirect to the news index. All of these figures rest on trade press quoting the releases.
- Whether £543m (Feb 2020) includes motor, and what its flood/wind split is. Only the March 2020 £363m split was found.
- Why the ABI's Feb 2025 release implies 2023 ≈ £458m and 2022 ≈ £508m when the April 2024 release gave £573m and £421m (a revision or a definition change).
- Whether the £443m 2023 business figure includes freeze or business interruption.
- The text of the EA 2007 review and the Pitt Review. The PDFs wouldn't render here; the quotes come from search excerpts and a CII summary. There is still no ABI-authored primary for the 2007 £3bn.
- The licence on the current EA RoFRS postcode file and on Recorded Flood Outlines, and whether the 2026 postcode revision reflects NaFRA2.
- The JRC depth-damage licence and MCM licence fees.
- Scottish dwelling count, and the PRA Rulebook rule number for the 99.5% calibration.
- The UK content of the Lloyd's RDS 2025/2026 specifications (PDFs unreadable here).
- The CCRA4-IA flooding and windstorm chapter findings.
