// UK Climate Risk: one page, drawn in plain JavaScript and SVG from the JSON climate_risk/model.py writes.

const view = document.getElementById("view");
const load = (name) => fetch(`data/${name}.json`).then((r) => {
  if (!r.ok) throw new Error(`${name}.json: ${r.status}`);
  return r.json();
});

// ---------- Formatting ----------

const esc = (s) => String(s).replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
const num = (n, digits = 0) => Number(n).toLocaleString("en-GB", { minimumFractionDigits: digits, maximumFractionDigits: digits });
// £1.4bn, £350m, £12m: three significant figures at most, so tables stay short.
function money(v) {
  if (v >= 1e9) return `£${num(v / 1e9, v >= 1e10 ? 0 : 1)}bn`;
  if (v >= 1e6) return `£${num(v / 1e6, v >= 1e7 ? 0 : 1)}m`;
  if (v >= 1e5) return `£${num(v / 1e3)}k`;
  return "under £0.1m";
}
const pct = (x) => `${x > 0 ? "+" : ""}${num(x)}%`;
const ukDate = new Intl.DateTimeFormat("en-GB", { day: "numeric", month: "short", year: "numeric" });
const day = (iso) => ukDate.format(new Date(iso));

// ---------- Tooltip ----------

const tip = Object.assign(document.createElement("div"), { className: "tip", role: "tooltip" });
document.body.append(tip);
function showTip(target, x, y) {
  const [title, ...rest] = target.dataset.tip.split("\n");
  tip.innerHTML = `<strong>${esc(title)}</strong>${rest.map((l) => `<span>${esc(l)}</span>`).join("")}`;
  tip.classList.add("on");
  const left = Math.min(Math.max(x + 14, 8), innerWidth - tip.offsetWidth - 8);
  const top = y - tip.offsetHeight - 14 < 8 ? y + 20 : y - tip.offsetHeight - 14;
  tip.style.transform = `translate(${left}px, ${top}px)`;
}
document.addEventListener("pointermove", (e) => {
  const target = e.target.closest?.("[data-tip]");
  if (target) showTip(target, e.clientX, e.clientY);
  else tip.classList.remove("on");
}, { passive: true });
document.addEventListener("focusin", (e) => {
  const target = e.target.closest?.("[data-tip]");
  if (!target) return tip.classList.remove("on");
  const box = target.getBoundingClientRect();
  showTip(target, box.left + box.width / 2, box.top);
});

// ---------- Chart helpers ----------

const scale = (d0, d1, r0, r1) => (v) => r0 + ((v - d0) / (d1 - d0 || 1)) * (r1 - r0);
const pathOf = (points) => points.map(([x, y], i) => `${i ? "L" : "M"}${x.toFixed(1)},${y.toFixed(1)}`).join("");
const legend = (items) => `<ul class="legend">${items.map(([c, label]) => `<li style="--c:${c}">${esc(label)}</li>`).join("")}</ul>`;
const width = (el) => Math.max(el.clientWidth, 280);

// A tidy step for a y axis that runs to max: 1, 2 or 5 times a power of ten, about five gridlines.
function niceStep(max) {
  const raw = max / 5;
  const power = 10 ** Math.floor(Math.log10(raw));
  return [1, 2, 5, 10].map((m) => m * power).find((s) => s >= raw);
}

// ---------- Exceedance curve ----------

function drawCurve(el, gb) {
  const w = width(el), h = 320, pad = { top: 16, right: 20, bottom: 40, left: 56 };
  const years = gb.curve.map((c) => c.years);
  const sx = scale(Math.log10(years[0]), Math.log10(years.at(-1)), pad.left, w - pad.right);
  const yMax = Math.max(...gb.curve.map((c) => c.total));
  const step = niceStep(yMax / 1e9) * 1e9;
  const top = Math.ceil(yMax / step) * step;
  const sy = scale(0, top, h - pad.bottom, pad.top);
  const grid = [], labels = [];
  for (let v = 0; v <= top; v += step) {
    grid.push(`<line x1="${pad.left}" x2="${w - pad.right}" y1="${sy(v)}" y2="${sy(v)}"/>`);
    labels.push(`<text x="${pad.left - 8}" y="${sy(v) + 4}" text-anchor="end">£${num(v / 1e9)}bn</text>`);
  }
  for (const y of years) labels.push(`<text x="${sx(Math.log10(y))}" y="${h - 20}" text-anchor="middle">1 in ${y}</text>`);
  labels.push(`<text x="${(pad.left + w - pad.right) / 2}" y="${h - 2}" text-anchor="middle">Return period (years, log scale)</text>`);
  const line = (key, cls) => `<path class="line ${cls}" d="${pathOf(gb.curve.map((c) => [sx(Math.log10(c.years)), sy(c[key])]))}"/>`;
  const x200 = sx(Math.log10(200));
  const dots = gb.curve.map((c) => `<circle class="dot total" r="5" cx="${sx(Math.log10(c.years))}" cy="${sy(c.total)}" tabindex="0"
      data-tip="${esc(`A 1-in-${c.years} year\nTotal ${money(c.total)}\nWindstorm alone ${money(c.storm)}\nFlood alone ${money(c.flood)}`)}"/>`);
  el.innerHTML = `<svg viewBox="0 0 ${w} ${h}" role="img" aria-label="Annual loss against return period">
      <g class="grid">${grid.join("")}</g>
      <g class="axis">${labels.join("")}</g>
      <line class="marker" x1="${x200}" x2="${x200}" y1="${pad.top}" y2="${h - pad.bottom}"/>
      <text class="chart-label strong" x="${x200 - 6}" y="${pad.top + 12}" text-anchor="end">Solvency II: 1 in 200</text>
      ${line("flood", "flood")}${line("storm", "storm")}${line("total", "total")}${dots.join("")}
    </svg>`;
}

// ---------- 47 years as if they happened today ----------

function drawHistory(el, gb) {
  const w = width(el), h = 280, pad = { top: 16, right: 12, bottom: 28, left: 56 };
  const rows = gb.history;
  const totals = rows.map((r) => r.storm + (r.flood ?? 0));
  const step = niceStep(Math.max(...totals) / 1e9) * 1e9;
  const top = Math.ceil(Math.max(...totals) / step) * step;
  const sy = scale(0, top, h - pad.bottom, pad.top);
  const band = (w - pad.left - pad.right) / rows.length;
  const grid = [], labels = [], bars = [];
  for (let v = 0; v <= top; v += step) {
    grid.push(`<line x1="${pad.left}" x2="${w - pad.right}" y1="${sy(v)}" y2="${sy(v)}"/>`);
    labels.push(`<text x="${pad.left - 8}" y="${sy(v) + 4}" text-anchor="end">£${num(v / 1e9, step < 1e9 ? 1 : 0)}bn</text>`);
  }
  rows.forEach((r, i) => {
    const x = pad.left + i * band + band * 0.12, bw = band * 0.76;
    const flood = r.flood ?? 0;
    const tipText = `${r.year}\nWindstorm ${money(r.storm)}\nFlood ${r.flood == null ? "no data before 2006" : money(flood)}`;
    bars.push(`<g tabindex="0" data-tip="${esc(tipText)}">
        <rect x="${x - band * 0.12}" y="${pad.top}" width="${band}" height="${h - pad.top - pad.bottom}" fill="transparent"/>
        <rect class="bar storm" x="${x}" width="${bw}" y="${sy(r.storm)}" height="${sy(0) - sy(r.storm)}" rx="1.5"/>
        <rect class="bar flood" x="${x}" width="${bw}" y="${sy(r.storm + flood)}" height="${sy(r.storm) - sy(r.storm + flood)}" rx="1.5"/>
      </g>`);
    if (r.year % 5 === 0) labels.push(`<text x="${x + bw / 2}" y="${h - 8}" text-anchor="middle">${r.year}</text>`);
  });
  el.innerHTML = `<svg viewBox="0 0 ${w} ${h}" role="img" aria-label="Modelled loss in each year since 1979">
      <g class="grid">${grid.join("")}</g><g class="axis">${labels.join("")}</g>${bars.join("")}
    </svg>`;
}

// ---------- Where the losses fall ----------

// Pale sand to deep teal, by risk cost per property.
function shade(value, max) {
  const t = Math.sqrt(Math.min(value / max, 1));
  const [a, b] = [[238, 231, 210], [31, 84, 98]];
  return `rgb(${a.map((v, i) => Math.round(v + (b[i] - v) * t)).join(",")})`;
}

function drawMap(el, map, regions) {
  const max = Math.max(...regions.map((r) => r.risk_cost_per_property));
  const paths = regions.map((r) => `<path d="${map.regions[r.region_id]}" fill="${shade(r.risk_cost_per_property, max)}" tabindex="0"
      data-tip="${esc(`${r.region}\n£${num(r.risk_cost_per_property)} a year per property\nWindstorm ${money(r.storm_eal)}, flood ${money(r.flood_eal)}${r.flood_coverage === "full" ? "" : `\nFlood: ${r.flood_coverage === "none" ? "not covered (Scotland)" : "English areas only"}`}`)}"/>`);
  el.innerHTML = `<svg viewBox="${map.viewBox}" role="img" aria-label="Map of risk cost per property by region">${paths.join("")}</svg>
    <div class="scale" style="--lo:${shade(0, max)};--hi:${shade(max, max)}"><span>£0</span><i></i><span>£${num(max)} a year per property</span></div>`;
}

const COLUMNS = [
  ["region", "Region", (r) => esc(r.region)],
  ["risk_cost_per_property", "Risk cost per property", (r) => `£${num(r.risk_cost_per_property)}`],
  ["storm_eal", "Windstorm EAL", (r) => money(r.storm_eal)],
  ["flood_eal", "Flood EAL", (r) => (r.flood_coverage === "none" ? `<span class="faint">no data</span>` : money(r.flood_eal) + (r.flood_coverage === "partial" ? "*" : ""))],
  ["rp10", "1-in-10", (r) => money(r.rp10)],
  ["rp200", "1-in-200", (r) => money(r.rp200)],
];

function drawTable(el, regions, sortKey = "risk_cost_per_property") {
  const rows = [...regions].sort((a, b) => (sortKey === "region" ? a.region.localeCompare(b.region) : b[sortKey] - a[sortKey]));
  el.innerHTML = `<table>
      <thead><tr>${COLUMNS.map(([key, label]) => `<th${key === sortKey ? ' aria-sort="descending"' : ""}><button data-sort="${key}">${label}</button></th>`).join("")}</tr></thead>
      <tbody>${rows.map((r) => `<tr>${COLUMNS.map(([, , cell]) => `<td>${cell(r)}</td>`).join("")}</tr>`).join("")}</tbody>
    </table>`;
  el.querySelectorAll("[data-sort]").forEach((b) => b.addEventListener("click", () => drawTable(el, regions, b.dataset.sort)));
}

// ---------- Frequency x severity ----------

function frequencyTable(regions) {
  const rows = [...regions].sort((a, b) => b.eal - a.eal);
  return `<table>
      <thead><tr><th>Region</th><th>Storm days a year</th><th>Loss per storm day</th><th>Flood days a year</th><th>Loss per flood day</th></tr></thead>
      <tbody>${rows.map((r) => `<tr><td>${esc(r.region)}</td><td>${num(r.storm_days_per_year, 1)}</td><td>${money(r.storm_loss_per_day)}</td>
        <td>${r.flood_coverage === "none" ? '<span class="faint">–</span>' : num(r.flood_days_per_year, 1)}</td>
        <td>${r.flood_coverage === "none" ? '<span class="faint">–</span>' : money(r.flood_loss_per_day)}</td></tr>`).join("")}</tbody>
    </table>`;
}

// ---------- Model against the ABI ----------

function checksTable(checks) {
  const verdict = (ratio) => (ratio >= 0.75 && ratio <= 1.33 ? "good" : ratio >= 0.5 && ratio <= 2 ? "off" : "bad");
  const roles = { calibration: "calibration", overlap: "partly test", test: "test" };
  return `<table>
      <thead><tr><th>Event</th><th>ABI reported</th><th>Model: wind</th><th>Model: flood</th><th>Model ÷ ABI</th></tr></thead>
      <tbody>${checks.map((c) => `<tr>
          <td class="role-${c.role}" data-role="${roles[c.role]}">${esc(c.name)}<br><span class="faint">${day(c.start)} to ${day(c.end)} · ${esc(c.abi_note)}</span></td>
          <td>${money(c.abi)}</td><td>${money(c.model_storm)}</td><td>${money(c.model_flood)}</td>
          <td class="ratio ${verdict(c.ratio)}">${num(c.ratio, 2)}×</td></tr>`).join("")}</tbody>
    </table>`;
}

// ---------- Sensitivity ----------

function sensitivityTable(sens) {
  const base = sens.variants[0];
  return `<table>
      <thead><tr><th>Change</th><th>Average year</th><th>1-in-200</th><th>1-in-200 against base</th></tr></thead>
      <tbody>${sens.variants.map((v, i) => `<tr${i ? "" : ' class="base"'}>
          <td>${esc(v.name)}${v.group ? `<br><span class="faint">${esc(v.group)}</span>` : ""}</td>
          <td>${money(v.eal)}</td><td>${money(v.rp200)}</td>
          <td>${i ? pct(100 * (v.rp200 / base.rp200 - 1)) : "–"}</td></tr>`).join("")}</tbody>
    </table>`;
}

// ---------- Wind and prices ----------

function drawPrices(el, prices) {
  const w = width(el), h = 280, pad = { top: 24, right: 12, bottom: 44, left: 48 };
  const values = prices.deciles.map((d) => d.vs_month_pct);
  const lim = Math.ceil(Math.max(...values.map(Math.abs)) / 5) * 5;
  const sy = scale(-lim, lim, h - pad.bottom, pad.top);
  const band = (w - pad.left - pad.right) / values.length;
  const grid = [], labels = [], bars = [];
  for (let v = -lim; v <= lim; v += 5) {
    grid.push(`<line x1="${pad.left}" x2="${w - pad.right}" y1="${sy(v)}" y2="${sy(v)}"/>`);
    labels.push(`<text x="${pad.left - 8}" y="${sy(v) + 4}" text-anchor="end">${pct(v)}</text>`);
  }
  prices.deciles.forEach((d, i) => {
    const x = pad.left + i * band + band * 0.15, bw = band * 0.7, v = d.vs_month_pct;
    bars.push(`<rect class="bar ${v > 0 ? "up" : "down"}" x="${x}" width="${bw}" y="${Math.min(sy(v), sy(0))}" height="${Math.abs(sy(v) - sy(0))}" rx="3" tabindex="0"
        data-tip="${esc(`${i === 0 ? "Calmest" : i === 9 ? "Windiest" : `Wind band ${d.decile}`} tenth of days\nAverage wind ${num(d.wind_ms, 1)} m/s at 100 m\nPower ${pct(v)} against that month's average\nAverage price ${num(d.price_p, 1)}p per kWh`)}"/>`);
    labels.push(`<text x="${x + bw / 2}" y="${h - 26}" text-anchor="middle">${num(d.wind_ms, 1)}</text>`);
  });
  labels.push(`<text x="${pad.left}" y="${h - 6}">Calmest days</text>`, `<text x="${w - pad.right}" y="${h - 6}" text-anchor="end">Windiest days (m/s at 100 m)</text>`);
  el.innerHTML = `<svg viewBox="0 0 ${w} ${h}" role="img" aria-label="Agile price against that month's average, by wind">
      <g class="grid">${grid.join("")}</g><line class="zero" x1="${pad.left}" x2="${w - pad.right}" y1="${sy(0)}" y2="${sy(0)}"/>
      <g class="axis">${labels.join("")}</g>${bars.join("")}
    </svg>`;
}

// ---------- Page ----------

async function render() {
  const [gb, regions, checks, sens, prices, meta, map] = await Promise.all([
    load("gb"), load("regions"), load("checks"), load("sensitivity"), load("prices"), load("meta"),
    fetch("map.json").then((r) => r.json()),
  ]);
  const byCost = [...regions].sort((a, b) => b.risk_cost_per_property - a.risk_cost_per_property);
  const tests = checks.filter((c) => c.role === "test");
  const rp200s = sens.variants.map((v) => v.rp200);
  const [low, high] = [Math.min(...rp200s), Math.max(...rp200s)];
  const worst = gb.worst_storm_days[0];
  const worstYear = gb.history.reduce((a, b) => (a.storm + (a.flood ?? 0) > b.storm + (b.flood ?? 0) ? a : b));

  view.innerHTML = `<div class="page">
    <section class="hero">
      <h1>A <span class="big">${money(gb.rp200)}</span> year<span class="soft">is this model's 1-in-200 for UK windstorm and flood</span></h1>
      <p>I ran 47 years of storms (${meta.storm_years[0]}–${meta.storm_years[1]}) and 20 years of flood warnings
        (${meta.flood_years[0]}–${meta.flood_years[1]}) against a hypothetical portfolio of all
        ${num(gb.properties / 1e6, 1)} million properties in Great Britain, then simulated ${num(meta.simulated_years)} years.
        It's calibrated on ABI claims and checked against past events.</p>
      <p class="caveat">An illustrative model, built to learn the method, so treat the figures as rough. Other reasonable
        modelling choices put the 1-in-200 anywhere from ${money(low)} to ${money(high)}: see the sensitivity check.</p>
      <ul class="figures">
        <li><strong>${money(gb.eal)}</strong><span>Average year (EAL)</span></li>
        <li><strong>${money(gb.rp10)}</strong><span>1-in-10 year</span></li>
        <li><strong>${money(gb.rp200)}</strong><span>1-in-200 year</span></li>
      </ul>
    </section>

    <section class="card">
      <div class="card-head">
        <h2>Expected annual loss by region, as a cost per property</h2>
        <p class="lede">${esc(byCost[0].region)} has the highest risk cost at £${num(byCost[0].risk_cost_per_property)} a property a year,
          mostly from flood. ${esc(byCost.at(-1).region)} has the lowest at £${num(byCost.at(-1).risk_cost_per_property)}.</p>
      </div>
      <div class="map-layout">
        <div class="map" id="map"></div>
        <div>
          <div class="table-wrap" id="regions"></div>
          <p class="note">Risk cost per property is EAL ÷ properties: the pure premium, before expenses, reinsurance and profit.
            Return-period losses aren't additive, so the regional 1-in-10s and 1-in-200s don't sum to the GB figures.
            Click a column to sort. *English flood areas only; the Environment Agency doesn't cover Scotland or Wales.</p>
        </div>
      </div>
    </section>

    <section class="card">
      <div class="card-head">
        <h2>Exceedance curve: annual loss by return period</h2>
        <p class="lede">Windstorm drives the tail: ${money(gb.storm_rp200)} on its own in a 1-in-200 year, against
          ${money(gb.flood_rp200)} for flood. Flood happens most years, so it drives the average.</p>
      </div>
      ${legend([["var(--total)", "Windstorm and flood"], ["var(--storm)", "Windstorm alone"], ["var(--flood)", "Flood alone"]])}
      <div class="chart" id="curve"></div>
      <p class="note">Each point is the annual loss with that chance of being exceeded in a year (an AEP curve), from
        ${num(meta.simulated_years)} simulated years. Solvency II sets capital at the 1-in-200, the 99.5% one-year VaR.</p>
    </section>

    <section class="card">
      <div class="card-head">
        <h2>Sensitivity: how far the 1-in-200 moves</h2>
        <p class="lede">Changing one choice at a time, and recalibrating each run, moves the 1-in-200 from ${money(low)} to
          ${money(high)}. Simulation noise is small next to that: ten random seeds give ${money(sens.seed_rp200[0])} to
          ${money(sens.seed_rp200[1])}.</p>
      </div>
      <div class="table-wrap">${sensitivityTable(sens)}</div>
      <ul class="method checks">
        <li><strong>Calibration matters most.</strong> With one gust point per region, February 2020 and 2022 imply very
          different windstorm scales, and the tail follows whichever one you trust.</li>
        <li><strong>The tail is the uncertain part.</strong> Each run is recalibrated to the ABI figures, so the average year
          moves far less than the 1-in-200.</li>
        <li><strong>47 years is a short record.</strong> Redrawing the historical years with replacement
          (${sens.history_runs} times) gives a 1-in-200 of ${money(sens.history_rp200[0])} to
          ${money(sens.history_rp200[2])} (10th to 90th percentile).</li>
      </ul>
    </section>

    <section class="card">
      <div class="card-head">
        <h2>As-if losses: each year since ${meta.storm_years[0]} replayed on today's properties</h2>
        <p class="lede">The worst was ${worstYear.year} at ${money(worstYear.storm + (worstYear.flood ?? 0))}. The costliest single day was
          ${day(worst.day)} (${money(worst.loss)})${worst.day === "1990-01-25" ? ", the Burns' Day storm" : ""}.</p>
      </div>
      ${legend([["var(--storm)", "Windstorm"], ["var(--flood)", "Flood (from 2006)"]])}
      <div class="chart" id="history"></div>
    </section>

    <section class="card">
      <div class="card-head">
        <h2>Frequency and severity: how often each region has a loss day, and how big</h2>
        <p class="lede">Storm days are about as common everywhere, because each region's threshold is its own 98th-percentile gust.
          What changes is how many properties are exposed.</p>
      </div>
      <div class="table-wrap">${frequencyTable(regions)}</div>
    </section>

    <section class="card">
      <div class="card-head">
        <h2>Back-test: the model against what insurers actually paid</h2>
        <p class="lede">Only ${tests.length} of ${checks.length} events are clean tests, and the model is far too low on both.
          February 2020 and 2022 set the windstorm scale, and the 2023 storms fall in the year flood is calibrated on.</p>
      </div>
      <div class="table-wrap">${checksTable(checks)}</div>
      <ul class="method checks">
        <li><strong>Calibration.</strong> Windstorm on the wind part of February 2020 and 2022 together (the ABI put 2020 at 41% wind).
          Flood on the ABI's 2023 weather claims, less burst pipes (${money(gb.abi_2023)}).</li>
        <li><strong>2020 too high, 2022 too low.</strong> With one gust point per region, 2020's gusts look far worse than 2022's. 2020
          also had a burst of flood warnings, and each counts the same whether one home floods or a hundred.</li>
        <li><strong>2023 not fully independent.</strong> The model barely sees Ciarán, whose strongest winds were on the south coast,
          so the match comes from flood, which is calibrated on 2023.</li>
        <li><strong>2015 and 2007 far too low.</strong> A warning says where water is expected, not how deep. 2007 was mostly surface
          water, which warnings don't cover.</li>
      </ul>
    </section>

    <section class="card">
      <div class="card-head"><h2>Method and limits</h2></div>
      <ul class="method">
        <li><strong>Exposure.</strong> Every property connected in the 14 electricity regions, about ${num(gb.properties / 1e6, 1)} million
          (rounded DNO customer numbers). The policies are hypothetical; the property counts are real.</li>
        <li><strong>Windstorm hazard and damage.</strong> The strongest gust each day at one point per region (ERA5). Following Klawa and Ulbrich (2003), only
          gusts above that point's own 98th percentile do damage, and loss grows with the cube of the excess.</li>
        <li><strong>Flood hazard and damage.</strong> Every Flood Warning and Severe Flood Warning the Environment Agency issued since 2006, placed in a region
          by its flood area's centre. Each warning is a fixed loss, £${num(gb.flood_scale_per_warning / 1e3)}k after calibration.</li>
        <li><strong>As-if basis.</strong> Every past year runs against today's properties and claim costs, so the years can be compared.</li>
        <li><strong>Simulation.</strong> Frequency × severity for each region and peril: a Poisson number of loss days a year, each drawn from history, with a
          generalised Pareto tail on the largest 10% so a day can be worse than any on record. GB is fitted on national loss days,
          so one storm can hit many regions at once.</li>
        <li><strong>Not included.</strong> Surface water, coastal surge outside warnings, subsidence and freeze. Losses are ground-up:
          no deductibles or limits, no buildings and contents split, no demand surge and no secondary uncertainty.</li>
        <li><strong>Next.</strong> This is today's climate. A +2°C scenario (UKCP18) is next.</li>
      </ul>
    </section>

    <section class="card">
      <div class="card-head">
        <h2>Side analysis: power price against that month's average, by how windy the day was</h2>
        <p class="lede">The calmest tenth of days cost ${num(prices.calm_vs_month_pct)}% more than their month's average, and the
          windiest tenth ${num(-prices.windy_vs_month_pct)}% less. The ${num(prices.storm_days)} days with damaging gusts in three or
          more regions, the days that drive claims, were ${num(-prices.storm_vs_month_pct)}% cheaper.</p>
      </div>
      <div class="chart" id="prices"></div>
      <p class="note">Storms bring a lot of wind power, so heavy property-claim days tend to be cheap-power days. That matters to a
        group writing both property and energy risks. Data: ${num(prices.days)} days, ${day(prices.from)} to ${day(prices.to)}. The
        Octopus Agile price is averaged across the 14 regions and compared with its month's average, so the 2022 spike doesn't
        swamp the pattern.</p>
    </section>
  </div>`;

  const redraw = () => {
    drawCurve(document.getElementById("curve"), gb);
    drawHistory(document.getElementById("history"), gb);
    drawPrices(document.getElementById("prices"), prices);
  };
  drawMap(document.getElementById("map"), map, regions);
  drawTable(document.getElementById("regions"), regions);
  redraw();
  let pending;
  addEventListener("resize", () => { clearTimeout(pending); pending = setTimeout(redraw, 150); });
  document.getElementById("updated").textContent = `Model run ${day(meta.built)}.`;
}

render().catch((error) => {
  view.innerHTML = `<p class="loading">Couldn't load the data: ${esc(error.message)}</p>`;
});
