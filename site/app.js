// Clean Power 2030: is Britain on track for 95% clean electricity by 2030? Two cross-filtered
// pages read the JSON exported from the Azure SQL mart views: "Are we on track?" (#/) and
// "Where and when?" (#/where). The region picker in the nav filters both, and clicking the map
// sets it. The "right now" tile calls the Carbon Intensity API from the browser.

// The Azure Function publishes fresh data to Blob Storage every morning; site/data is the copy
// published with the site, used if Blob Storage can't be reached. Anywhere but the live site
// (a local preview), the local copy comes first.
const BLOB = "https://stgridcarbon108eb8.blob.core.windows.net/data";
const DATA_SOURCES = location.hostname.endsWith("github.io") ? [BLOB, "data"] : ["data", BLOB];
const LIVE_API = "https://api.carbonintensity.org.uk";

const TARGET = 95;            // Clean Power 2030: at least 95% of GB generation from clean sources
const OFFICIAL_2025 = 73.3;   // DESNZ's own 2025 figure, which counts a slightly different set of fuels
const GAS_ALLOWED = 5;        // the gas share Clean Power 2030 leaves room for, at most

const REGIONS = {
  18: "Great Britain", 15: "England", 16: "Scotland", 17: "Wales",
  1: "North Scotland", 2: "South Scotland", 3: "North West England", 4: "North East England", 5: "Yorkshire",
  6: "North Wales & Merseyside", 7: "South Wales", 8: "West Midlands", 9: "East Midlands", 10: "East England",
  11: "South West England", 12: "South England", 13: "London", 14: "South East England",
};
const CLEAN = ["wind", "solar", "hydro", "biomass", "nuclear"];
// The bar race and the tooltips: [column in gb_annual, label, colour].
const MIX = [
  ["wind", "Wind", "var(--wind)"],
  ["gas", "Gas", "var(--gas)"],
  ["nuclear", "Nuclear", "var(--nuclear)"],
  ["other_clean", "Biomass & hydro", "var(--biomass)"],
  ["solar", "Solar", "var(--solar)"],
  ["coal", "Coal", "var(--coal)"],
  ["other", "Other", "var(--other)"],
];
const LIVE_FUELS = {
  wind: "var(--wind)", solar: "var(--solar)", hydro: "var(--hydro)", biomass: "var(--biomass)", nuclear: "var(--nuclear)",
  gas: "var(--gas)", coal: "var(--coal)", imports: "var(--other)", other: "var(--other)",
};
const TECHS = ["Offshore wind", "Onshore wind", "Solar", "Batteries"];
const STATUS = [[1, "var(--green)", "on pace"], [0.8, "var(--amber)", "a little behind"], [0, "var(--rust)", "well behind"]];
const WIND_BANDS = {
  Calm: ["Under 4 m/s, 100 m up", "var(--gas)"],
  Breezy: ["4 to 10 m/s", "var(--biomass)"],
  Windy: ["10 m/s and over", "var(--wind)"],
};

const view = document.getElementById("view");
const regionSelect = document.getElementById("region");
const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
const files = {};
const state = { region: 18, season: "Winter" };
let navigation = 0;
let onResize = null;  // the current page's chart redraw, called when the window is resized

async function fetchJson(name) {
  let lastError;
  for (const base of DATA_SOURCES) {
    try {
      const response = await fetch(`${base}/${name}.json`, { cache: "no-cache" });
      if (response.ok) return await response.json();
      lastError = new Error(`${name}.json: ${response.status}`);
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError;
}
const load = (name) => (files[name] ??= fetchJson(name).catch((error) => {
  delete files[name];  // let the next visit try again
  throw error;
}));
const loadMap = () => (files.map ??= fetch("map.json").then((r) => r.json()));

// ---------- Formatting ----------

const esc = (s) => String(s).replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
const num = (n, digits = 0) => (n == null ? "–" : Number(n).toLocaleString("en-GB", { minimumFractionDigits: digits, maximumFractionDigits: digits }));
const pct = (x, digits = 0) => (x == null ? "–" : `${num(x, digits)}%`);
const pence = (x) => (x == null ? "–" : `${num(x, 1)}p`);
const hourLabel = (h) => `${String(h % 24).padStart(2, "0")}:00`;
const ampm = (h) => `${h % 12 || 12}${h < 12 ? "am" : "pm"}`;
const ukDate = new Intl.DateTimeFormat("en-GB", { timeZone: "Europe/London", day: "numeric", month: "short", year: "numeric" });
const ukClock = new Intl.DateTimeFormat("en-GB", { timeZone: "Europe/London", hour: "2-digit", minute: "2-digit" });
const TIMES = { 1: "as", 2: "twice", 3: "three times", 4: "four times", 5: "five times", 6: "six times" };
const times = (x) => TIMES[Math.round(x)] ?? `${num(x, 1)} times`;
const GREW = { 2: "doubled", 3: "tripled", 4: "quadrupled" };
const grew = (x) => GREW[Math.round(x)] ?? `grown ${num(x, 1)} times`;
const listOf = (items) => (items.length < 2 ? items.join("") : `${items.slice(0, -1).join(", ")} and ${items.at(-1)}`);
const capital = (s) => s.charAt(0).toUpperCase() + s.slice(1);
const regionName = (id) => REGIONS[id] ?? `Region ${id}`;
const compactRows = (n) => (n >= 1e6 ? `${Math.floor(n / 1e6)}M+` : num(n));

// Clean share as a colour: rust (dirty) through amber to leaf green (clean).
const RAMP = [[30, [192, 87, 47]], [62, [217, 150, 43]], [95, [82, 117, 37]]];
function cleanColour(value) {
  const v = Math.min(Math.max(value, RAMP[0][0]), RAMP[2][0]);
  const i = v <= RAMP[1][0] ? 0 : 1;
  const [v0, c0] = RAMP[i];
  const [v1, c1] = RAMP[i + 1];
  const t = (v - v0) / (v1 - v0);
  return `rgb(${c0.map((c, k) => Math.round(c + (c1[k] - c) * t)).join(",")})`;
}
const statusOf = (ratio) => STATUS.find(([min]) => ratio >= min);

// ---------- Motion ----------

function reveal(root) {
  const blocks = root.querySelectorAll(".reveal");
  if (reduceMotion || !("IntersectionObserver" in window)) {
    blocks.forEach((block) => block.classList.add("is-visible"));
    return;
  }
  const observer = new IntersectionObserver((entries) => entries.forEach((entry) => {
    if (!entry.isIntersecting) return;
    entry.target.classList.add("is-visible");
    observer.unobserve(entry.target);
  }), { threshold: 0.12 });
  blocks.forEach((block) => observer.observe(block));
}

// ---------- Tabs ----------

function tabs(options, selected, label) {
  const buttons = options.map((o) => `<button role="tab" aria-selected="${o === selected}" data-value="${esc(o)}">${esc(o)}</button>`).join("");
  return `<div class="tabs" role="tablist" aria-label="${esc(label)}"><span class="indicator"></span>${buttons}</div>`;
}
function moveIndicator(bar) {
  const on = bar.querySelector('[aria-selected="true"]');
  const indicator = bar.querySelector(".indicator");
  if (!on || !indicator) return;
  indicator.style.width = `${on.offsetWidth}px`;
  indicator.style.transform = `translateX(${on.offsetLeft}px)`;
}
function wireTabs(bar, onPick) {
  moveIndicator(bar);
  bar.addEventListener("click", (e) => {
    const button = e.target.closest("button[data-value]");
    if (!button || button.getAttribute("aria-selected") === "true") return;
    bar.querySelectorAll("button").forEach((b) => b.setAttribute("aria-selected", b === button));
    moveIndicator(bar);
    onPick(button.dataset.value);
  });
}

// ---------- Tooltip: one for the page, fed by data-tip attributes or by the charts ----------

const tip = Object.assign(document.createElement("div"), { className: "tip", role: "tooltip" });
document.body.append(tip);
let tipOwner = null;
function showTip(lines, x, y, owner) {
  if (owner !== tipOwner || owner == null) {
    const [title, ...rest] = lines;
    tip.innerHTML = `<strong>${esc(title)}</strong>${rest.map((l) => `<span>${esc(l)}</span>`).join("")}`;
    tipOwner = owner;
  }
  tip.classList.add("on");
  const left = Math.min(Math.max(x + 14, 8), innerWidth - tip.offsetWidth - 8);
  const top = y - tip.offsetHeight - 14 < 8 ? y + 20 : y - tip.offsetHeight - 14;
  tip.style.transform = `translate(${left}px, ${top}px)`;
}
function hideTip() {
  tip.classList.remove("on");
  tipOwner = null;
}
document.addEventListener("pointermove", (e) => {
  const target = e.target.closest?.("[data-tip]");
  if (target) showTip(target.dataset.tip.split("\n"), e.clientX, e.clientY, target);
  else if (tipOwner instanceof Element) hideTip();
}, { passive: true });
document.addEventListener("focusin", (e) => {
  const target = e.target.closest?.("[data-tip]");
  if (!target) return hideTip();
  const box = target.getBoundingClientRect();
  showTip(target.dataset.tip.split("\n"), box.left + box.width / 2, box.top, target);
});

// ---------- SVG charts with a numeric x axis ----------

const scale = (d0, d1, r0, r1) => (v) => r0 + ((v - d0) / (d1 - d0 || 1)) * (r1 - r0);
const pathOf = (points) => points.map(([x, y], i) => `${i ? "L" : "M"}${x.toFixed(1)},${y.toFixed(1)}`).join("");

// lines: [{ points: [[x, y]], cls, draw }], dots: [[x, y, cls]], labels: [[x, y, text, cls, anchor]].
// area: { points, yMax } is drawn against a second y axis on the right (prices).
// hover(x) returns { x, y, lines } for the nearest point, or null.
function xyChart(el, { x0, x1, yMax, yStep, height = 300, xTicks, unit = "%", lines = [], dots = [], labels = [], bands = [], area, hover }) {
  const width = Math.max(el.clientWidth, 280);
  const pad = { top: 16, right: area ? 44 : 16, bottom: 28, left: 40 };
  const sx = scale(x0, x1, pad.left, width - pad.right);
  const sy = scale(0, yMax, height - pad.bottom, pad.top);
  const grid = [];
  const yLabels = [];
  for (let v = 0; v <= yMax; v += yStep) {
    grid.push(`<line x1="${pad.left}" x2="${width - pad.right}" y1="${sy(v)}" y2="${sy(v)}"/>`);
    yLabels.push(`<text x="${pad.left - 8}" y="${sy(v) + 4}" text-anchor="end">${num(v)}${v + yStep > yMax ? unit : ""}</text>`);
  }
  let areaSvg = "";
  if (area) {
    const sy2 = scale(0, area.yMax, height - pad.bottom, pad.top);
    const pts = area.points.map(([x, y]) => [sx(x), sy2(y)]);
    areaSvg = `<path class="area price" d="${pathOf(pts)}L${pts.at(-1)[0]},${sy2(0)}L${pts[0][0]},${sy2(0)}Z"/>
      <path class="line price" d="${pathOf(pts)}"/>`;
    for (let v = 0; v <= area.yMax; v += area.yStep) {
      yLabels.push(`<text x="${width - pad.right + 8}" y="${sy2(v) + 4}">${num(v)}${v + area.yStep > area.yMax ? "p" : ""}</text>`);
    }
  }
  const xLabels = xTicks.map(([x, label]) => `<text x="${sx(x)}" y="${height - 6}" text-anchor="middle">${esc(label)}</text>`);
  const bandSvg = bands.map(([from, to, cls, label]) => `<rect class="${cls}" x="${sx(from)}" y="${pad.top}" width="${sx(to) - sx(from)}" height="${height - pad.top - pad.bottom}" rx="4"/>
      ${label ? `<text class="chart-label" x="${(sx(from) + sx(to)) / 2}" y="${pad.top + 14}" text-anchor="middle">${esc(label)}</text>` : ""}`);
  const lineSvg = lines.map((l) => `<path class="line ${l.cls}${l.draw === false ? "" : ` draw" pathLength="1000" style="--len:1000`}" d="${pathOf(l.points.map(([x, y]) => [sx(x), sy(y)]))}"/>`);
  const dotSvg = dots.map(([x, y, cls]) => `<circle class="dot ${cls}" cx="${sx(x)}" cy="${sy(y)}" r="5"/>`);
  const labelSvg = labels.map(([x, y, text, cls = "", anchor = "start"]) => `<text class="chart-label ${cls}" x="${sx(x)}" y="${sy(y)}" text-anchor="${anchor}">${esc(text)}</text>`);
  el.innerHTML = `<svg viewBox="0 0 ${width} ${height}" role="img">
      <g class="grid">${grid.join("")}</g>
      ${bandSvg.join("")}
      ${areaSvg}
      <g class="axis">${yLabels.join("")}${xLabels.join("")}</g>
      ${lineSvg.join("")}${dotSvg.join("")}${labelSvg.join("")}
      <line class="hover-line" y1="${pad.top}" y2="${height - pad.bottom}"/>
      <circle class="hover-dot" r="4"/>
    </svg>`;
  if (!hover) return;
  const svg = el.querySelector("svg");
  const hoverLine = svg.querySelector(".hover-line");
  const dot = svg.querySelector(".hover-dot");
  const leave = () => { el.classList.remove("is-hover"); hideTip(); };
  svg.addEventListener("pointermove", (e) => {
    const box = svg.getBoundingClientRect();
    const px = ((e.clientX - box.left) / box.width) * width;
    const point = hover(x0 + ((px - pad.left) / (width - pad.left - pad.right)) * (x1 - x0));
    if (!point) return leave();
    hoverLine.setAttribute("x1", sx(point.x));
    hoverLine.setAttribute("x2", sx(point.x));
    dot.setAttribute("cx", sx(point.x));
    dot.setAttribute("cy", point.y == null ? -10 : sy(point.y));
    el.classList.add("is-hover");
    showTip(point.lines, e.clientX, e.clientY, `${el.id}-${point.x}`);
  });
  svg.addEventListener("pointerleave", leave);
}

// ---------- Shared pieces ----------

const factRows = (s) => s.gb_generation_rows + s.national_periods + s.national_mix_rows + s.regional_periods
  + s.regional_mix_rows + s.weather_rows + s.price_rows + s.capacity_rows;

// How the page is made, drawn as a power line: data flows from the APIs on the left to this page
// on the right. Each stop has a hover note with the detail.
const ukDay = new Intl.DateTimeFormat("en-GB", { timeZone: "Europe/London", weekday: "short", day: "numeric", month: "short" });

async function powerLine() {
  const [summary, checks, meta] = await Promise.all([load("summary"), load("data_checks"), load("meta")]);
  const s = summary[0];
  const blocking = checks.filter((c) => c.is_blocking);
  const blockingFailed = blocking.some((c) => c.failures);
  const warnings = checks.filter((c) => !c.is_blocking && c.failures);
  const updated = new Date(meta.exported_at);
  const today = ukDay.format(updated) === ukDay.format(new Date());
  const stops = [
    [`${s.sources} public APIs`, "NESO, Octopus and more",
      ["Where the data comes from", "NESO Data Portal: generation since 2009 and the 2030 capacity plans", "Carbon Intensity API: the regional mix",
        "Octopus Energy: Agile prices", "Open-Meteo: wind speed", `${num(s.api_downloads)} downloads, ${num(s.raw_mb_compressed)} MB compressed`]],
    ["Python", "on Azure, every morning",
      ["Azure Function", "A timer runs it at 05:30 each morning", "It fetches only what's new and saves the raw JSON"]],
    ["Azure SQL", `${compactRows(factRows(s))} rows`,
      ["Azure SQL database", "T-SQL turns the raw JSON into a star schema", "Views do the sums for each chart on this page"]],
    [`${checks.length} checks`, blockingFailed ? "a blocking check failed" : warnings.length ? `run daily, ${warnings.length} flag API gaps` : "run daily, all passing",
      ["Data quality checks, every run", `${blocking.length - blocking.filter((c) => c.failures).length} of ${blocking.length} blocking checks pass (a failure stops the export)`,
        ...warnings.map((c) => `Warning: ${c.check_name.toLowerCase()} (${num(c.failures)})`)]],
    ["This page", today ? "updated today" : `updated ${ukDate.format(updated)}`,
      ["The dashboard", "Plain JavaScript and hand-drawn SVG charts", "No chart libraries"]],
  ];
  return `<section class="powerline" aria-label="How this page is made">
      <span class="powerline__wire" aria-hidden="true"><span class="powerline__pulse"></span></span>
      <ol>${stops.map(([title, note, tip], i) => `<li class="powerline__stop${i === stops.length - 1 ? " is-end" : ""}" tabindex="0" data-tip="${esc(tip.join("\n"))}">
        <strong>${esc(title)}</strong><span>${esc(note)}</span>
      </li>`).join("")}</ol>
    </section>`;
}

const regionL12m = (summary, id) => summary.find((r) => r.period === "L12M" && r.region_id === id);

// ---------- Page 1: Are we on track? ----------

async function renderTrack(ticket) {
  const [annual, onTrack, capacity, regions, map, stack] = await Promise.all([
    load("gb_annual"), load("on_track"), load("capacity"), load("region_summary"), loadMap(), powerLine(),
  ]);
  if (ticket !== navigation) return;
  const t = onTrack[0];
  const years = annual.filter((r) => /^\d{4}$/.test(r.period)).map((r) => ({ ...r, year: Number(r.period) }));
  const lastPeriod = new Date(t.last_period_utc);
  const fullYears = years.filter((r) => r.year < lastPeriod.getUTCFullYear());
  const change = t.clean_l12m - t.clean_p12m;
  const picked = state.region !== 18 ? regionL12m(regions, state.region) : null;
  const build = buildOut(capacity);
  const gap = build.find((b) => b.tech === "Offshore wind") ?? build.at(-1);
  const l12m = regions.filter((r) => r.period === "L12M");
  const local = l12m.filter((r) => !r.is_aggregate && r.clean_pct != null).sort((a, b) => b.clean_pct - a.clean_pct);

  view.innerHTML = `<div class="page">
    <div class="band">
    <section class="hero">
      <div>
        <p class="eyebrow">Great Britain · last 12 months</p>
        <h1><span class="big">${pct(t.clean_l12m)}</span> clean.<span class="soft">The target is ${TARGET}% by 2030.</span></h1>
        <div class="progress" role="img" aria-label="${pct(t.clean_l12m)} of the way to 100%, target ${TARGET}%">
          <div class="progress__track"><span class="progress__fill" style="--w:${t.clean_l12m}%"></span></div>
          <span class="progress__mark" style="--x:${TARGET}%"><span>2030 target</span></span>
          <div class="progress__scale"><span>0%</span><span>100%</span></div>
        </div>
        <p>${change >= 0 ? "Up" : "Down"} ${num(Math.abs(change))} point${Math.round(Math.abs(change)) === 1 ? "" : "s"} on the year before.
          (The government's own measure, which leaves out a few fuels, put 2025 at ${num(OFFICIAL_2025)}%.)</p>
        ${picked ? `<p class="region-note">${esc(regionName(state.region))} ran on ${pct(picked.clean_pct)} clean power over the same 12 months.</p>` : ""}
      </div>
      <aside class="live" aria-live="polite"><div class="live__label"><span class="live__dot"></span>Right now</div><p class="faint">Loading…</p></aside>
    </section>
    ${stack}
    </div>

    <section class="card reveal" id="trajectory">
      <div class="card-head"><div>
        <h2>Clean power since 2009</h2>
        <p class="lede">It has ${grew(t.clean_l12m / t.clean_2009)}, but it needs to grow ${times(t.pace_ratio)} faster to hit 95% by 2030.</p>
      </div></div>
      <div class="chart" id="trajectory-chart"></div>
      <ul class="legend">
        <li><i style="--c:var(--accent)"></i>What happened</li>
        <li><i class="dash" style="--c:var(--amber)"></i>Needed: ${num(t.needed_pace, 1)} points a year</li>
        <li><i class="dot" style="--c:var(--gas)"></i>Current pace: ${num(t.recent_pace, 1)} a year, about ${pct(t.projected_2030)} by 2030</li>
        ${picked ? `<li><i style="--c:var(--wind)"></i>${esc(regionName(state.region))}</li>` : ""}
      </ul>
    </section>

    <section class="card reveal" id="race">
      <div class="card-head"><div>
        <h2>Where our electricity comes from</h2>
        <p class="lede">${raceHeadline(fullYears)}</p>
      </div></div>
      <div class="race"></div>
    </section>

    <section class="card reveal" id="regions">
      <div class="card-head"><div>
        <h2>Clean power by region</h2>
        <p class="lede">${esc(local[0].region_name)} is the cleanest at ${pct(local[0].clean_pct)}. ${esc(local.at(-1).region_name)} is the least clean at ${pct(local.at(-1).clean_pct)}. Click a region to filter the page.</p>
      </div></div>
      <div class="map-layout map-layout--small">
        <div class="map${state.region !== 18 ? " has-pick" : ""}">${mapSvg(map, l12m, state.region)}</div>
        <div>
          <ol class="rank">${[...local.slice(0, 3), ...local.slice(-3)].map((r, i) => `${i === 3 ? '<li class="rank__gap" aria-hidden="true">…</li>' : ""}<li><button data-region="${r.region_id}" aria-pressed="${r.region_id === state.region}">
              <span>${esc(r.region_name)}</span><span class="bar" style="--w:${r.clean_pct}%;--c:${cleanColour(r.clean_pct)}"></span><span class="val">${pct(r.clean_pct)}</span>
            </button></li>`).join("")}</ol>
          <div class="scale"><span>Less clean</span><i></i><span>More clean</span></div>
          <a class="more" href="#/where">All regions and times of day &rarr;</a>
        </div>
      </div>
    </section>

    <section class="card reveal" id="build">
      <div class="card-head"><div>
        <h2>Building for 2030</h2>
        <p class="lede">${buildHeadline(build)}</p>
      </div></div>
      <div class="build">
        <div class="build-head" aria-hidden="true"><span></span><span></span><span>Built</span><span>Planned</span><span>Needed</span><span></span></div>
        ${build.map(buildRow).join("")}
      </div>
      <ul class="legend">
        <li><i class="box" style="--c:var(--gas)"></i>Built</li>
        <li><i class="box faded" style="--c:var(--gas)"></i>Planned by 2030</li>
        <li><i class="line-mark"></i>Needed by 2030</li>
        <li><i class="box" style="--c:var(--green)"></i>On pace</li>
        <li><i class="box" style="--c:var(--amber)"></i>A little behind</li>
        <li><i class="box" style="--c:var(--rust)"></i>Well behind</li>
      </ul>
    </section>

    <section class="card reveal verdict" id="verdict">
      <p class="eyebrow">Summary</p>
      <h2>Building is mostly on track. <span class="bad">${esc(gap.tech)} and gas aren't.</span></h2>
      <div class="facts">
        ${build.filter((b) => b.ratio >= 1).slice(0, 1).map((b) => `<div class="fact" style="--c:var(--green)"><strong>${pct(b.ratio * 100)}</strong><span>of the ${b.tech.toLowerCase()} 2030 needs are on course to be built. Ahead of plan.</span></div>`).join("")}
        <div class="fact" style="--c:var(--rust)"><strong>${num(gap.outlook)} of ${num(gap.target)} GW</strong><span>${esc(gap.tech.toLowerCase())} on course for 2030. It's the biggest gap.</span></div>
        <div class="fact" style="--c:var(--gas)"><strong>${pct(t.gas_l12m)} gas</strong><span>in the last 12 months. Clean Power 2030 leaves room for about ${GAS_ALLOWED}%.</span></div>
      </div>
    </section>
  </div>`;

  const draw = () => drawTrajectory(years, fullYears, t, picked ? regions.filter((r) => r.region_id === state.region) : null);
  draw();
  onResize = () => { draw(); view.querySelectorAll(".build-detail:not([hidden])").forEach((d) => drawBuildDetail(d, capacity)); };
  wireBuild(capacity);
  view.querySelectorAll("#regions .map path, #regions .rank button").forEach((el) => el.addEventListener("click", () => pickRegion(Number(el.dataset.region))));
  bar_race(view.querySelector(".race"), years, lastPeriod);
  reveal(view);
  renderLive(ticket);
}

// The live tile: the clean share of what's being generated in the selected region this half-hour.
async function renderLive(ticket) {
  const box = view.querySelector(".live");
  const id = state.region;
  try {
    const json = await fetch(id === 18 ? `${LIVE_API}/generation` : `${LIVE_API}/regional/regionid/${id}`).then((r) => r.json());
    if (ticket !== navigation) return;
    const period = id === 18 ? json.data : json.data[0].data[0];
    const mix = period.generationmix;
    const share = (fuel) => mix.find((f) => f.fuel === fuel)?.perc ?? 0;
    const clean = CLEAN.reduce((sum, fuel) => sum + share(fuel), 0);
    const value = (100 * clean) / Math.max(100 - share("imports"), 1);
    const shown = mix.filter((f) => f.perc > 0 && f.fuel !== "imports").sort((a, b) => b.perc - a.perc);
    const total = shown.reduce((sum, f) => sum + f.perc, 0);
    box.innerHTML = `<div class="live__label"><span class="live__dot"></span>Right now</div>
      <div class="live__value">${pct(value)}<small>clean</small></div>
      <p class="live__where">${esc(regionName(id))}, ${ukClock.format(new Date(period.from))}</p>
      <div class="stack" data-tip="${esc(["Generating this half-hour", ...shown.map((f) => `${capital(f.fuel)}: ${pct((100 * f.perc) / total, 1)}`)].join("\n"))}">
        ${shown.map((f) => `<span style="width:${(100 * f.perc) / total}%;--c:${LIVE_FUELS[f.fuel] ?? "var(--other)"}"></span>`).join("")}
      </div>`;
  } catch (error) {
    console.warn("Live tile:", error);
    if (ticket === navigation) box.innerHTML = `<div class="live__label">Right now</div><p class="faint">The live figure didn't load. National Grid's API is sometimes busy, so try again in a minute.</p>`;
  }
}

function mixLines(r) {
  return MIX.filter(([key]) => r[`${key}_pct`] >= 0.5).sort((a, b) => r[`${b[0]}_pct`] - r[`${a[0]}_pct`])
    .map(([key, label]) => `${label}: ${pct(r[`${key}_pct`])}`);
}

function drawTrajectory(years, fullYears, t, regionRows) {
  const el = document.getElementById("trajectory-chart");
  const last = new Date(t.last_period_utc);
  const nowX = last.getUTCFullYear() + last.getUTCMonth() / 12 - 0.5 + last.getUTCDate() / 365;  // middle of the last 12 months
  const actual = [...fullYears.map((r) => [r.year + 0.5, r.clean_pct]), [nowX, t.clean_l12m]];
  const end = 2030.5;
  const lines = [
    { points: [[nowX, t.clean_l12m], [end, TARGET]], cls: "needed later", draw: false },
    { points: [[nowX, t.clean_l12m], [end, t.projected_2030]], cls: "pace later", draw: false },
    { points: actual, cls: "actual" },
  ];
  if (regionRows) {
    const points = regionRows.filter((r) => /^\d{4}$/.test(r.period) && Number(r.period) >= 2019 && Number(r.period) < last.getUTCFullYear())
      .map((r) => [Number(r.period) + 0.5, r.clean_pct]);
    const l12m = regionRows.find((r) => r.period === "L12M");
    if (l12m) points.push([nowX, l12m.clean_pct]);
    lines.push({ points, cls: "region" });
  }
  const narrow = el.clientWidth < 560;
  xyChart(el, {
    x0: 2009, x1: 2031, yMax: 100, yStep: 25, height: narrow ? 260 : 340,
    xTicks: (narrow ? [2010, 2020, 2030] : [2010, 2014, 2018, 2022, 2026, 2030]).map((y) => [y + 0.5, String(y)]),
    lines,
    dots: [[nowX, t.clean_l12m, "actual"], [end, TARGET, "needed later"], [end, t.projected_2030, "pace later"]],
    labels: [
      [end - 0.3, TARGET + 4, `${TARGET}% needed`, "strong later", "end"],
      [end - 0.3, t.projected_2030 - 9, `${pct(t.projected_2030)} at today's pace`, "later", "end"],
      [nowX - 0.4, t.clean_l12m + 7, `Now ${pct(t.clean_l12m)}`, "strong", "end"],
    ],
    hover: (x) => {
      if (x > nowX + 0.4) {
        const year = Math.min(Math.max(Math.round(x - 0.5), Math.ceil(nowX)), 2030);
        const at = (to) => t.clean_l12m + ((to - t.clean_l12m) * (year + 0.5 - nowX)) / (end - nowX);
        return { x: year + 0.5, y: at(TARGET), lines: [String(year), `Needed: ${pct(at(TARGET))}`, `At today's pace: ${pct(at(t.projected_2030))}`] };
      }
      if (x > fullYears.at(-1).year + 1) {
        return { x: nowX, y: t.clean_l12m, lines: ["Last 12 months", `Clean: ${pct(t.clean_l12m, 1)}`, ...mixLines(years.find((r) => r.period === "L12M") ?? {})] };
      }
      const r = fullYears.find((y) => y.year === Math.round(x - 0.5));
      if (!r) return null;
      const region = regionRows?.find((row) => row.period === r.period);
      return { x: r.year + 0.5, y: r.clean_pct, lines: [r.period, `Clean: ${pct(r.clean_pct, 1)}`, ...mixLines(r),
        ...(region?.clean_pct != null ? [`${regionName(state.region)}: ${pct(region.clean_pct)}`] : [])] };
    },
  });
}

// ---------- Bar race: the mix year by year ----------

function raceHeadline(years) {
  const coalPeak = years.reduce((a, b) => (b.coal_pct > a.coal_pct ? b : a));
  const latest = years.at(-1);
  const coalNow = latest.coal_pct < 0.5 ? "zero" : pct(latest.coal_pct);
  return `Coal went from ${pct(coalPeak.coal_pct)} to ${coalNow}. Wind went from ${pct(years[0].wind_pct)} to ${pct(latest.wind_pct)}.`;
}

function bar_race(el, years, lastPeriod) {
  const frames = years.map((r) => ({ ...r, label: r.year === lastPeriod.getUTCFullYear() ? `${r.year} so far` : r.period }));
  const max = Math.max(...frames.flatMap((r) => MIX.map(([key]) => r[`${key}_pct`])));
  const last = frames.length - 1;
  const DURATION = 16000;  // the whole race, 2009 to now, glides through each year at an even speed
  el.innerHTML = `<div class="race__rows" style="--rows:${MIX.length}">
      ${MIX.map(([key, label, colour]) => `<div class="race__row" data-key="${key}" style="--c:${colour}">
        <span class="race__name">${esc(label)}</span>
        <span class="race__bar"><span class="race__fill"></span><span class="race__value"></span></span>
      </div>`).join("")}
    </div>
    <div class="race__year" aria-hidden="true"></div>
    <div class="race__controls"></div>`;
  const rows = [...el.querySelectorAll(".race__row")];
  const yearLabel = el.querySelector(".race__year");
  const controls = el.querySelector(".race__controls");
  let position = 0;  // a fractional frame: 3.5 is halfway between the 4th and 5th year
  let frame = null;

  // Draw any point between two years by blending their shares, so bars grow and overtake smoothly.
  const show = (at) => {
    position = at;
    const i = Math.min(Math.floor(at), last);
    const a = frames[i];
    const b = frames[Math.min(i + 1, last)];
    const t = at - i;
    const value = (key) => a[`${key}_pct`] + (b[`${key}_pct`] - a[`${key}_pct`]) * t;
    const order = MIX.map(([key]) => key).sort((x, y) => value(y) - value(x));
    rows.forEach((row) => {
      const v = value(row.dataset.key);
      row.style.setProperty("--rank", order.indexOf(row.dataset.key));
      row.style.setProperty("--w", `${(v / max) * 88}%`);
      row.querySelector(".race__value").textContent = pct(v, v < 10 ? 1 : 0);
    });
    const shown = frames[Math.round(at)];
    yearLabel.textContent = shown.label;
    el.setAttribute("aria-label", `${shown.label}: ${mixLines(shown).join(", ")}`);
  };
  const stop = () => {
    cancelAnimationFrame(frame);
    frame = null;
    el.classList.remove("is-playing");
  };
  // Glide from where the bars are now to another year; used by the slider after the race.
  const glide = (to, ms) => {
    stop();
    const from = position;
    const started = performance.now();
    const ticket = navigation;
    const step = (now) => {
      if (ticket !== navigation) return stop();
      const k = Math.min((now - started) / ms, 1);
      show(from + (to - from) * (1 - (1 - k) ** 3));
      frame = k < 1 ? requestAnimationFrame(step) : null;
    };
    frame = requestAnimationFrame(step);
  };
  const finish = () => {
    stop();
    show(last);
    controls.innerHTML = `<button class="btn" data-act="replay" aria-label="Play again">&#8635; Replay</button>
      <input type="range" min="0" max="${last}" step="1" value="${last}" aria-label="Year">`;
    controls.querySelector("input").addEventListener("input", (e) => glide(Number(e.target.value), 450));
    controls.querySelector("[data-act=replay]").addEventListener("click", play);
  };
  function play() {
    stop();
    controls.innerHTML = `<button class="btn race__skip" data-act="skip">Skip &rarr;</button>`;
    controls.querySelector("[data-act=skip]").addEventListener("click", finish);
    el.classList.add("is-playing");
    const started = performance.now();
    const ticket = navigation;
    const step = (now) => {
      if (ticket !== navigation) return stop();
      const at = ((now - started) / DURATION) * last;
      if (at >= last) return finish();
      show(at);
      frame = requestAnimationFrame(step);
    };
    frame = requestAnimationFrame(step);
  }
  show(0);
  if (reduceMotion || !("IntersectionObserver" in window)) return finish();
  controls.innerHTML = `<button class="btn race__skip" data-act="skip">Skip &rarr;</button>`;
  controls.querySelector("[data-act=skip]").addEventListener("click", finish);
  const observer = new IntersectionObserver(([entry]) => {
    if (!entry.isIntersecting) return;
    observer.disconnect();
    if (frame == null && position === 0) play();
  }, { threshold: 0.45 });
  observer.observe(el);
}

// ---------- Build-out: capacity against 2030 ----------

function buildOut(capacity) {
  return TECHS.map((tech) => {
    const rows = capacity.filter((r) => r.technology === tech);
    const actuals = rows.filter((r) => r.basis === "actual").sort((a, b) => a.year - b.year);
    const latest = actuals.at(-1);
    const outlook = rows.find((r) => r.basis === "outlook")?.gw;
    const target = rows.find((r) => r.basis === "target")?.gw;
    if (!latest || outlook == null || target == null) return null;
    const ratio = outlook / target;
    const [, colour, word] = statusOf(ratio);
    return { tech, actuals, built: latest.gw, builtYear: latest.year, outlook, target, ratio, colour, word };
  }).filter(Boolean);
}

function buildHeadline(build) {
  const by = (word) => build.filter((b) => b.word === word).map((b) => b.tech.toLowerCase());
  const ahead = by("on pace");
  const worst = build.reduce((a, b) => (b.ratio < a.ratio ? b : a));
  const close = by("a little behind").filter((n) => n !== worst.tech.toLowerCase());
  const parts = [];
  const verb = (names) => (names.length > 1 || names[0].endsWith("s") ? "are" : "is");
  if (ahead.length) parts.push(`${capital(listOf(ahead))} ${verb(ahead)} on pace.`);
  if (close.length) parts.push(`${capital(listOf(close))} ${verb(close)} close.`);
  parts.push(`${worst.tech} is the gap: ${num(worst.built)} GW built, ${num(worst.target)} GW needed.`);
  return parts.join(" ");
}

function buildRow(b) {
  const top = Math.max(b.target, b.outlook, b.built) * 1.08;
  const at = (gw) => `${(gw / top) * 100}%`;
  const tipText = [b.tech, `Built: ${num(b.built, 1)} GW (end of ${b.builtYear})`, `On course for: ${num(b.outlook, 1)} GW by 2030`,
    `Needed: ${num(b.target, 1)} GW by 2030`, `${capital(b.word)}: ${pct(b.ratio * 100)} of what's needed`].join("\n");
  return `<button class="build-row" data-tech="${esc(b.tech)}" aria-expanded="false" data-tip="${esc(tipText)}" style="--c:${b.colour}">
      <span class="build-name">${esc(b.tech)}</span>
      <span class="build-track">
        <span class="build-plan" style="--w:${at(b.outlook)}"></span>
        <span class="build-fill" style="--w:${at(b.built)}"></span>
        <span class="build-target" style="--x:${at(b.target)}"></span>
      </span>
      <span class="build-num"><strong>${num(b.built)}</strong> GW</span>
      <span class="build-num">${num(b.outlook)} GW</span>
      <span class="build-num">${num(b.target)} GW</span>
      <span class="build-chev" aria-hidden="true">&rsaquo;</span>
      <span class="build-note"><b>${capital(b.word)}.</b> ${buildNote(b)}</span>
    </button>
    <div class="build-detail" data-tech="${esc(b.tech)}" hidden></div>`;
}

// Plans as a share of what's needed, in words.
function buildNote(b) {
  const share = pct(b.ratio * 100);
  return b.ratio >= 1 ? `Plans reach ${share} of what 2030 needs.` : `Plans reach ${share} of what 2030 needs, ${num(b.target - b.outlook)} GW short.`;
}

function wireBuild(capacity) {
  view.querySelectorAll(".build-row").forEach((row) => row.addEventListener("click", () => {
    const open = row.getAttribute("aria-expanded") === "true";
    view.querySelectorAll(".build-row").forEach((r) => r.setAttribute("aria-expanded", "false"));
    view.querySelectorAll(".build-detail").forEach((d) => { d.hidden = true; });
    if (open) return;
    row.setAttribute("aria-expanded", "true");
    const detail = row.nextElementSibling;
    detail.hidden = false;
    drawBuildDetail(detail, capacity);
  }));
}

function drawBuildDetail(detail, capacity) {
  const b = buildOut(capacity).find((x) => x.tech === detail.dataset.tech);
  const years = b.actuals.map((r) => [r.year, r.gw]);
  const yMax = Math.ceil((Math.max(b.target, b.outlook) * 1.1) / 10) * 10;
  const growth = (b.actuals.at(-1).gw - b.actuals[0].gw) / (b.actuals.at(-1).year - b.actuals[0].year);
  const needed = (b.target - b.built) / (2030 - b.builtYear);
  detail.innerHTML = `<p>Since ${b.actuals[0].year} we've added about ${num(growth, 1)} GW a year. Reaching ${num(b.target)} GW by 2030 takes ${num(needed, 1)} GW a year.</p><div class="chart" id="build-chart"></div>
    <ul class="legend"><li><i style="--c:var(--accent)"></i>Built</li><li><i class="dash" style="--c:var(--amber)"></i>Needed: ${num(b.target)} GW</li><li><i class="dot" style="--c:var(--gas)"></i>Planned: ${num(b.outlook)} GW</li></ul>`;
  const first = b.actuals[0].year;
  xyChart(detail.querySelector(".chart"), {
    x0: first - 0.3, x1: 2030.6, yMax, yStep: yMax > 40 ? 10 : 5, height: 220, unit: " GW",
    xTicks: [first, 2022, 2025, 2030].filter((y, i, a) => a.indexOf(y) === i && y >= first).map((y) => [y, String(y)]),
    lines: [
      { points: [[b.builtYear, b.built], [2030, b.target]], cls: "needed", draw: false },
      { points: [[b.builtYear, b.built], [2030, b.outlook]], cls: "pace", draw: false },
      { points: years, cls: "actual", draw: false },
    ],
    dots: [[2030, b.target, "target"], [2030, b.outlook, "pace"], [b.builtYear, b.built, "actual"]],
    hover: (x) => {
      const r = b.actuals.find((a) => a.year === Math.round(x));
      if (r) return { x: r.year, y: r.gw, lines: [String(r.year), `${num(r.gw, 1)} GW built`] };
      if (x > 2029) return { x: 2030, y: b.target, lines: ["2030", `Needed: ${num(b.target, 1)} GW`, `Plans: ${num(b.outlook, 1)} GW`] };
      return null;
    },
  });
}

// ---------- Page 2: Where and when? ----------

async function renderWhere(ticket) {
  const [regions, profile, wind, map, stack] = await Promise.all([
    load("region_summary"), load("region_profile"), load("region_wind"), loadMap(), powerLine(),
  ]);
  if (ticket !== navigation) return;
  const l12m = regions.filter((r) => r.period === "L12M");
  const local = l12m.filter((r) => !r.is_aggregate && r.clean_pct != null).sort((a, b) => b.clean_pct - a.clean_pct);
  const best = local[0];
  const worst = local.at(-1);
  const scotland = l12m.find((r) => r.region_id === 16);
  const id = state.region;
  const name = regionName(id);

  view.innerHTML = `<div class="page">
    <div class="band">
    <section class="hero hero--slim" style="grid-template-columns:1fr">
      <div>
        <p class="eyebrow">Last 12 months</p>
        <h1>Regions and times of day<span class="soft">Some places and hours are much cleaner than others.</span></h1>
      </div>
    </section>
    ${stack}
    </div>

    <section class="card reveal" id="map">
      <div class="card-head"><div>
        <h2>Clean power by region</h2>
        <p class="lede">${esc(best.region_name)} runs on ${pct(best.clean_pct)} clean power. ${esc(worst.region_name)} is at ${pct(worst.clean_pct)}. Click a region to filter the page.</p>
      </div></div>
      <div class="map-layout">
        <div class="map${id !== 18 ? " has-pick" : ""}">${mapSvg(map, l12m, id)}</div>
        <div>
          <ol class="rank">${local.map((r) => `<li><button data-region="${r.region_id}" aria-pressed="${r.region_id === id}">
              <span>${esc(r.region_name)}</span><span class="bar" style="--w:${r.clean_pct}%;--c:${cleanColour(r.clean_pct)}"></span><span class="val">${pct(r.clean_pct)}</span>
            </button></li>`).join("")}</ol>
          <div class="scale"><span>Less clean</span><i></i><span>More clean</span></div>
        </div>
      </div>
    </section>

    <section class="card reveal" id="wind">
      <div class="card-head"><div>
        <h2>Calm and windy days</h2>
        <p class="lede">${esc(name)}: ${windHeadline(wind.filter((w) => w.region_id === id)).replace(/^./, (c) => c.toLowerCase())}</p>
      </div></div>
      <div class="tiles">${wind.filter((w) => w.region_id === id).map(windTile).join("")}</div>
    </section>

    <section class="card reveal" id="day">
      <div class="card-head">
        <div>
          <h2>An average day</h2>
          <p class="lede">${esc(name)}: <span id="day-headline"></span></p>
        </div>
        ${tabs(["Winter", "Summer"], state.season, "Season")}
      </div>
      <div class="chart" id="day-chart"></div>
      <ul class="legend">
        <li><i style="--c:var(--accent)"></i>Clean share (left)</li>
        <li><i class="box" style="--c:var(--price-soft)"></i>Agile price, p per kWh (right)</li>
        <li><i class="box" style="--c:var(--peak-soft)"></i>4–7pm peak</li>
      </ul>
    </section>

    <section class="card reveal" id="so-what">
      <h2 class="actions-title">What would help</h2>
      <div class="actions">
        <article class="action"><span class="num">1</span><h3>Build offshore faster</h3>
          <p>It's the biggest gap to 2030. Today's plans fall well short of what the target needs.</p>
          <a href="#/track/build">See the build-out &rarr;</a></article>
        <article class="action"><span class="num">2</span><h3>Shift demand away from 4–7pm</h3>
          <p>The evening peak is when gas fills the gap and prices jump. EVs, heat pumps and batteries can wait a couple of hours.</p>
          <a href="#/where/day">See the average day &rarr;</a></article>
        <article class="action"><span class="num">3</span><h3>Connect Scottish wind to the South</h3>
          <p>Scotland's power is ${pct(scotland?.clean_pct)} clean, ${esc(worst.region_name)}'s ${pct(worst.clean_pct)}. More cables move clean power to where people use it.</p>
          <a href="#/where/map">See the map &rarr;</a></article>
      </div>
    </section>
  </div>`;

  view.querySelectorAll(".map path, .rank button").forEach((el) => el.addEventListener("click", () => pickRegion(Number(el.dataset.region))));
  view.querySelectorAll(".map path").forEach((el) => el.addEventListener("keydown", (e) => {
    if (e.key === "Enter" || e.key === " ") { e.preventDefault(); pickRegion(Number(el.dataset.region)); }
  }));
  const draw = () => drawDay(profile.filter((p) => p.region_id === id && p.season === state.season));
  wireTabs(view.querySelector("#day .tabs"), (season) => { state.season = season; draw(); });
  draw();
  onResize = () => { draw(); moveIndicator(view.querySelector("#day .tabs")); };
  reveal(view);
}

function mapSvg(map, l12m, picked) {
  const paths = Object.entries(map.regions).map(([id, d]) => {
    const r = l12m.find((x) => x.region_id === Number(id));
    if (!r) return "";
    const tipText = [r.region_name, `${pct(r.clean_pct)} clean`, `Wind ${pct(r.wind_pct)} · Gas ${pct(r.gas_pct)}`, "Click to filter"].join("\n");
    return `<path d="${d}" data-region="${id}" fill="${cleanColour(r.clean_pct)}" class="${Number(id) === picked ? "is-picked" : ""}"
      tabindex="0" role="button" aria-label="${esc(`${r.region_name}: ${pct(r.clean_pct)} clean`)}" data-tip="${esc(tipText)}"/>`;
  });
  return `<svg viewBox="${map.viewBox}" role="group" aria-label="Map of the 14 regions, coloured by clean share">${paths.join("")}</svg>`;
}

function pickRegion(id) {
  setRegion(state.region === id ? 18 : id);
}

function windHeadline(bands) {
  const calm = bands.find((b) => b.band === "Calm");
  const windy = bands.find((b) => b.band === "Windy");
  if (!calm || !windy) return "How the wind changes the mix.";
  if (calm.gas_pct > windy.gas_pct && calm.price > windy.price) return "Calm days burn more gas and cost more.";
  if (calm.gas_pct > windy.gas_pct) return "Calm days burn more gas.";
  return "Here the wind makes little difference to gas.";
}

function windTile(w) {
  const [when, colour] = WIND_BANDS[w.band];
  return `<article class="tile" style="--c:${colour}" data-tip="${esc([`${w.band} half-hours`, `${num(w.half_hours / 2)} hours in the last 12 months`, `Clean: ${pct(w.clean_pct)}`, `Gas: ${pct(w.gas_pct)}`, `Average Agile price: ${pence(w.price)} per kWh`].join("\n"))}">
      <h3>${esc(w.band)}</h3>
      <p class="when">${esc(when)} · ${pct(w.share_of_time * 100)} of the time</p>
      <div class="figure">${pct(w.gas_pct)}<small>gas</small></div>
      <div class="row"><span>Price</span><b>${pence(w.price)} per kWh</b></div>
      <div class="row"><span>Clean</span><b>${pct(w.clean_pct)}</b></div>
    </article>`;
}

function drawDay(rows) {
  const el = document.getElementById("day-chart");
  const headline = document.getElementById("day-headline");
  if (!rows.length) { el.innerHTML = `<p class="faint">No data for this region.</p>`; return; }
  rows = [...rows].sort((a, b) => a.hour_uk - b.hour_uk);
  const dirtiest = rows.reduce((a, b) => (b.clean_pct < a.clean_pct ? b : a));
  const dearest = rows.reduce((a, b) => (b.price > a.price ? b : a));
  const cleanest = rows.reduce((a, b) => (b.clean_pct > a.clean_pct ? b : a));
  const inPeak = (h) => h >= 16 && h < 19;
  headline.textContent = inPeak(dirtiest.hour_uk) && inPeak(dearest.hour_uk)
    ? `${cleanest.hour_uk >= 10 && cleanest.hour_uk <= 15 ? "midday" : "night"} is cleanest. The 4–7pm peak is the dirtiest and the most expensive.`
    : `cleanest around ${ampm(cleanest.hour_uk)}, dirtiest around ${ampm(dirtiest.hour_uk)} and dearest around ${ampm(dearest.hour_uk)}.`;
  const priceMax = Math.ceil(Math.max(...rows.map((r) => r.price)) / 10) * 10;
  const yMax = 100;
  const narrow = el.clientWidth < 560;
  xyChart(el, {
    x0: 0, x1: 23, yMax, yStep: 25, height: narrow ? 240 : 300,
    xTicks: (narrow ? [0, 6, 12, 18, 23] : [0, 3, 6, 9, 12, 15, 18, 21, 23]).map((h) => [h, h === 23 ? "23:00" : hourLabel(h)]),
    bands: [[16, 19, "peak-band", "4–7pm"]],
    area: { points: rows.map((r) => [r.hour_uk, r.price]), yMax: priceMax, yStep: priceMax / 4 },
    lines: [{ points: rows.map((r) => [r.hour_uk, r.clean_pct]), cls: "clean" }],
    hover: (x) => {
      const r = rows.find((row) => row.hour_uk === Math.round(x));
      return r && { x: r.hour_uk, y: r.clean_pct, lines: [`${hourLabel(r.hour_uk)}–${hourLabel(r.hour_uk + 1)}`, `Clean: ${pct(r.clean_pct)}`, `Gas: ${pct(r.gas_pct)}`, `Price: ${pence(r.price)} per kWh`] };
    },
  });
}

// ---------- Page 3: Method ----------

// The star schema: each fact table and the dimensions it joins to. Row counts come from the export.
const DIMS = [
  ["date", "dim.date", "One row per UK day, 2009 to 2030: year, month, weekday, season"],
  ["region", "dim.region", "The 14 network regions, the three nations and GB, with each region's Octopus tariff letter"],
  ["fuel", "dim.fuel", "Ten fuels, each flagged clean or not. This flag is the definition of clean used everywhere"],
  ["point", "dim.weather_point", "A weather point in each region, plus Dogger Bank for offshore wind"],
];
const FACTS = [
  ["fact.gb_generation", "gb_generation_rows", ["date", "fuel"], "Megawatts by fuel for every half-hour since 2009 (NESO). Columnstore"],
  ["fact.national_intensity", "national_periods", ["date"], "GB carbon intensity per half-hour, forecast and actual"],
  ["fact.national_mix", "national_mix_rows", ["date", "fuel"], "GB share by fuel per half-hour since 2018"],
  ["fact.regional_intensity", "regional_periods", ["date", "region"], "Each region's carbon intensity per half-hour"],
  ["fact.regional_mix", "regional_mix_rows", ["date", "region", "fuel"], "Each region's share by fuel per half-hour, the biggest table. Columnstore"],
  ["fact.price", "price_rows", ["date", "region"], "Octopus Agile price per region and half-hour"],
  ["fact.weather_hourly", "weather_rows", ["point"], "Hourly wind, sun and temperature at each point (ERA5)"],
  ["fact.capacity", "capacity_rows", [], "GW built, planned and needed by 2030 for four technologies"],
];

const SQL_PACE = `-- mart.v_on_track (shortened): the recent pace is a least-squares
-- slope through the last seven full years, so one odd year doesn't swing it.
fit AS (
    SELECT (COUNT(*) * SUM([year] * clean_pct) - SUM([year]) * SUM(clean_pct))
           / NULLIF(COUNT(*) * SUM(CAST([year] AS FLOAT) * [year])
                    - SUM(CAST([year] AS FLOAT)) * SUM([year]), 0) AS slope
    FROM years
)
SELECT n.l12m                                       AS clean_l12m,
       f.slope                                      AS recent_pace,
       (95 - n.l12m) / n.years_left                 AS needed_pace,
       n.l12m + f.slope * n.years_left              AS projected_2030
FROM now AS n CROSS JOIN fit AS f;`;

const SQL_CLEAN = `-- mart.v_gb_annual (simplified): the clean share of electricity generated
-- in Britain. Imports are left out of the total, as in the 95% target.
SELECT period,
       100.0 * SUM(CASE WHEN f.is_low_carbon = 1 THEN g.mw END) / SUM(g.mw) AS clean_pct
FROM fact.gb_generation AS g
JOIN dim.fuel AS f ON f.fuel_id = g.fuel_id
CROSS APPLY (VALUES (CAST(g.date_key / 10000 AS VARCHAR(4))),      -- calendar year
                    (CASE WHEN g.period_start_utc > @year_ago THEN 'L12M' END)
            ) AS t (period)
WHERE t.period IS NOT NULL AND f.fuel_key <> 'imports'
GROUP BY period;`;

// Let long table names wrap after a dot or underscore rather than mid-word.
const breakable = (name) => esc(name).replace(/([._])/g, "$1<wbr>");

const REPO = "https://github.com/tristanbowdenfreeman-maker/uk-grid-carbon/blob/main/sql";

async function renderMethod(ticket) {
  const [summary, checks, onTrack, stack] = await Promise.all([load("summary"), load("data_checks"), load("on_track"), powerLine()]);
  if (ticket !== navigation) return;
  const s = summary[0];
  const t = onTrack[0];
  const warnings = checks.filter((c) => !c.is_blocking && c.failures);

  view.innerHTML = `<div class="page">
    <div class="band">
    <section class="hero hero--slim" style="grid-template-columns:1fr">
      <div>
        <p class="eyebrow">How the numbers are made</p>
        <h1>Method and data<span class="soft">Definitions, caveats, the data model and the checks behind every chart.</span></h1>
      </div>
    </section>
    ${stack}
    </div>

    <section class="card reveal" id="definitions">
      <div class="card-head"><div><h2>Definitions</h2></div></div>
      <dl class="defs">
        <dt>Clean share</dt>
        <dd>Electricity generated in Great Britain from wind, solar, hydro, biomass and nuclear, as a share of all electricity generated in Britain. Imports are left out of the total, as they are in the Clean Power 2030 target.</dd>
        <dt>Last 12 months</dt>
        <dd>The 12 months to the latest settled half-hour, so the headline doesn't depend on the season. The 12 months before that are the comparison.</dd>
        <dt>Current pace</dt>
        <dd>A least-squares trend through the clean share of the last seven full years (${t.trend_from_year}–${t.trend_to_year}): ${num(t.recent_pace, 1)} points a year.</dd>
        <dt>Needed pace</dt>
        <dd>The straight line from the last 12 months to 95% in mid-2030: ${num(t.needed_pace, 1)} points a year over ${num(t.years_left, 1)} years.</dd>
        <dt>Built, planned and needed</dt>
        <dd>Built is the latest year in NESO's Future Energy Scenarios. Planned is where NESO's ten-year outlook expects 2030 to land. Needed is NESO's Clean Power 2030 capacity, the "starting point" in its resource adequacy work.</dd>
        <dt>Calm, breezy and windy</dt>
        <dd>Each half-hour is put in a band by the wind speed 100 m up at the region's weather point, about the height of a turbine hub.</dd>
      </dl>
    </section>

    <section class="card reveal" id="caveats">
      <div class="card-head"><div><h2>Caveats</h2></div></div>
      <ul class="caveats">
        <li><b>The 2030 projection is a straight line.</b> Real growth comes in steps as big offshore wind farms connect, so the path won't be smooth. It shows the gap, not a forecast.</li>
        <li><b>The headline isn't the official figure.</b> The government's own measure (DESNZ) put 2025 at ${num(OFFICIAL_2025)}%. It uses different source data and counts some fuels differently, so the two shouldn't be compared directly. The trend is what matters here, and it is measured the same way every year.</li>
        <li><b>Regional mixes are modelled.</b> The Carbon Intensity API estimates each region's mix from a power-flow model. They are not metered.</li>
        <li><b>Prices are one tariff.</b> Octopus Agile follows the wholesale market half-hour by half-hour. It is a good signal of when power is cheap, but it isn't the wholesale price itself.</li>
        <li><b>Weather is one point per region.</b> One point stands in for a whole region, so local conditions vary.</li>
        <li><b>Gaps in the source data.</b> ${warnings.length ? warnings.map((c) => `${c.check_name} (${num(c.failures)})`).join(", ") + ". These are gaps in the APIs, not a broken load, and each is under half a percent of the half-hours." : "None at the last run."}</li>
      </ul>
    </section>

    <section class="card reveal" id="model">
      <div class="card-head"><div>
        <h2>Data model</h2>
        <p class="lede">A star schema in Azure SQL with ${num(factRows(s))} fact rows. Raw JSON lands in a staging table and stored procedures load it into the facts and dimensions. One view per chart does the sums. Hover over a table to see what it holds.</p>
      </div></div>
      <div class="schema">
        <svg class="schema__links" aria-hidden="true"></svg>
        <div class="schema__col">
          <p class="schema__label">Facts</p>
          ${FACTS.map(([name, key, joins, note]) => `<div class="schema__table is-fact" data-joins="${joins.join(" ")}" tabindex="0" data-tip="${esc([name, note, joins.length ? `Joins: ${joins.join(", ")}` : "Stands alone"].join("\n"))}">
            <code data-name="${name}">${breakable(name)}</code><span>${compactRows(s[key])} rows</span></div>`).join("")}
        </div>
        <div class="schema__col">
          <p class="schema__label">Dimensions</p>
          ${DIMS.map(([key, name, note]) => `<div class="schema__table is-dim" data-dim="${key}" tabindex="0" data-tip="${esc([name, note].join("\n"))}"><code>${breakable(name)}</code></div>`).join("")}
        </div>
      </div>
      <ol class="layers">
        <li><code>stg</code> raw API responses, compressed</li>
        <li><code>dim</code> + <code>fact</code> the star schema</li>
        <li><code>mart</code> one view per chart</li>
        <li><code>etl</code> data checks, then the export</li>
      </ol>
    </section>

    <section class="card reveal" id="checks">
      <div class="card-head"><div>
        <h2>Data checks</h2>
        <p class="lede">These run after every daily load. If a blocking check fails, the export stops and the site keeps its last good data. Warnings are shown here.</p>
      </div></div>
      <div class="table-wrap"><table class="checks">
        <thead><tr><th>Check</th><th>Type</th><th class="num">Rows failing</th></tr></thead>
        <tbody>${checks.map((c) => `<tr><td>${esc(c.check_name)}</td><td>${c.is_blocking ? "Blocking" : "Warning"}</td>
          <td class="num"><span class="status ${c.failures ? (c.is_blocking ? "is-bad" : "is-warn") : "is-ok"}">${c.failures ? num(c.failures) : "Pass"}</span></td></tr>`).join("")}</tbody>
      </table></div>
    </section>

    <section class="card reveal" id="sql">
      <div class="card-head"><div>
        <h2>Key SQL</h2>
        <p class="lede">The two queries the headline rests on. The full scripts are <a href="${REPO}">on GitHub</a>.</p>
      </div></div>
      <div class="code-grid">
        <figure><figcaption>The clean share · <a href="${REPO}/4_marts/03_v_gb_annual.sql">03_v_gb_annual.sql</a></figcaption><pre><code>${esc(SQL_CLEAN)}</code></pre></figure>
        <figure><figcaption>Pace and projection · <a href="${REPO}/4_marts/04_v_on_track.sql">04_v_on_track.sql</a></figcaption><pre><code>${esc(SQL_PACE)}</code></pre></figure>
      </div>
    </section>
  </div>`;

  drawSchema();
  onResize = drawSchema;
  wireSchema();
  reveal(view);
}

// Lines from each fact table to the dimensions it joins, measured from where the boxes sit.
function drawSchema() {
  const box = view.querySelector(".schema");
  if (!box) return;
  const svg = box.querySelector(".schema__links");
  const origin = box.getBoundingClientRect();
  svg.setAttribute("viewBox", `0 0 ${origin.width} ${origin.height}`);
  const lines = [];
  box.querySelectorAll(".is-fact").forEach((fact) => {
    const a = fact.getBoundingClientRect();
    fact.dataset.joins.split(" ").filter(Boolean).forEach((key) => {
      const b = box.querySelector(`[data-dim="${key}"]`).getBoundingClientRect();
      const x1 = a.right - origin.left, y1 = a.top + a.height / 2 - origin.top;
      const x2 = b.left - origin.left, y2 = b.top + b.height / 2 - origin.top;
      const mid = (x1 + x2) / 2;
      lines.push(`<path data-fact="${fact.querySelector("code").dataset.name}" data-dim="${key}" d="M${x1},${y1} C${mid},${y1} ${mid},${y2} ${x2},${y2}"/>`);
    });
  });
  svg.innerHTML = lines.join("");
}

function wireSchema() {
  const box = view.querySelector(".schema");
  const light = (table) => {
    box.classList.toggle("is-focus", !!table);
    box.querySelectorAll(".schema__table").forEach((t) => t.classList.remove("is-on"));
    box.querySelectorAll(".schema__links path").forEach((p) => p.classList.remove("is-on"));
    if (!table) return;
    table.classList.add("is-on");
    const match = table.classList.contains("is-fact")
      ? (p) => p.dataset.fact === table.querySelector("code").dataset.name
      : (p) => p.dataset.dim === table.dataset.dim;
    box.querySelectorAll(".schema__links path").forEach((p) => {
      if (!match(p)) return;
      p.classList.add("is-on");
      box.querySelectorAll(`[data-dim="${p.dataset.dim}"].schema__table`).forEach((t) => table.classList.contains("is-fact") && t.classList.add("is-on"));
      if (table.classList.contains("is-dim")) [...box.querySelectorAll(".is-fact")].find((f) => f.querySelector("code").dataset.name === p.dataset.fact)?.classList.add("is-on");
    });
  };
  box.querySelectorAll(".schema__table").forEach((t) => {
    t.addEventListener("pointerenter", () => light(t));
    t.addEventListener("focus", () => light(t));
    t.addEventListener("pointerleave", () => light(null));
    t.addEventListener("blur", () => light(null));
  });
}

// ---------- Region filter and routing ----------

regionSelect.innerHTML = [18, 15, 16, 17, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]
  .map((id) => `<option value="${id}">${esc(regionName(id))}</option>`).join("");
regionSelect.addEventListener("change", () => setRegion(Number(regionSelect.value)));

function setRegion(id) {
  state.region = id;
  regionSelect.value = String(id);
  regionSelect.parentElement.classList.toggle("is-set", id !== 18);
  const y = scrollY;
  route(false).then(() => scrollTo({ top: y, behavior: "instant" }));
}

function renderError(message) {
  view.innerHTML = `<div class="page hero"><div><h1>No data</h1><p>${esc(message)}</p></div></div>`;
}

async function route(fresh = true) {
  const ticket = ++navigation;
  onResize = null;
  hideTip();
  const [, page, anchor] = (location.hash || "#/").split("/");
  const section = page === "where" || page === "method" ? page : "track";
  regionSelect.parentElement.hidden = section === "method";
  document.querySelectorAll("[data-nav]").forEach((link) => link.toggleAttribute("aria-current", link.dataset.nav === section));
  try {
    await ({ where: renderWhere, method: renderMethod }[section] ?? renderTrack)(ticket);
  } catch (error) {
    if (ticket === navigation) renderError(`Couldn't load the data (${error.message}).`);
    return;
  }
  if (!fresh || ticket !== navigation) return;
  const target = anchor && document.getElementById(anchor);
  if (target) {
    target.classList.add("is-visible");
    target.scrollIntoView({ behavior: reduceMotion ? "auto" : "smooth" });
  } else scrollTo({ top: 0 });
}

window.addEventListener("hashchange", () => route());
let resizeTimer;
window.addEventListener("resize", () => {
  clearTimeout(resizeTimer);
  resizeTimer = setTimeout(() => onResize?.(), 150);
});

const nav = document.querySelector(".site-nav");
const onScroll = () => {
  const max = document.documentElement.scrollHeight - innerHeight;
  nav.classList.toggle("is-scrolled", scrollY > 24);
  nav.style.setProperty("--progress", max > 0 ? (scrollY / max).toFixed(4) : 0);
};
window.addEventListener("scroll", onScroll, { passive: true });
new ResizeObserver(onScroll).observe(document.body);

load("meta").then((meta) => {
  document.getElementById("updated").textContent = `Data updated ${ukDate.format(new Date(meta.exported_at))}.`;
}).catch(() => {});
route();
