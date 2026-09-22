// Run the real vegetationState() against a year of real weather.
//
// The model was wrong twice before it was right, and both times only running it
// against actual climates showed it: the first invented a season at the equator,
// the second gave Kyoto Montreal's autumn. So the fixtures are the test, and
// this is what drives them. Same shape as extract.mjs — the function under test
// is lifted from the QML every run, never copied.

import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { load, extractNumber, QML_PATH } from "./extract.mjs";

const DIR = new URL("./fixtures/climate/", import.meta.url);
export const PLACES = readdirSync(fileURLToPath(DIR)).filter((f) => f.endsWith(".json"))
                        .map((f) => f.replace(".json", "")).sort();

// Every leaf* constant, read from the QML rather than restated here: tuning the
// model without re-running these is then impossible.
const SRC = readFileSync(QML_PATH, "utf8");
const TUNING = Object.fromEntries(
  [...SRC.matchAll(/property (?:real|int) (leaf\w+):/g)].map((m) => [m[1], extractNumber(SRC, m[1])]));
const R = load(["vegetationState"], TUNING).root;

// Day length and how fast it is changing, from the standard sunrise equation.
// The plugin takes both from the forecast's own sunrise and sunset times; here
// they are computed, because a fixture is a year of climate and not a year of
// ephemeris.
export function dayLen(lat, doy) {
  const p = Math.asin(0.39795 * Math.cos(0.2163108
            + 2 * Math.atan(0.9671396 * Math.tan(0.00860 * (doy - 186)))));
  const x = (Math.sin(0.8333 * Math.PI / 180) + Math.sin(lat * Math.PI / 180) * Math.sin(p))
          / (Math.cos(lat * Math.PI / 180) * Math.cos(p));
  return 24 - (24 / Math.PI) * Math.acos(Math.max(-1, Math.min(1, x)));
}

// A fixture as the plugin's climProc would leave it: monthly means, monthly
// rain and PET, and the year's aridity.
export function climOf(place) {
  const j = JSON.parse(readFileSync(new URL(`${place}.json`, DIR), "utf8"));
  const mt = Array(12).fill(0), mp = Array(12).fill(0), me = Array(12).fill(0), n = Array(12).fill(0);
  const d0 = new Date(j.start + "T00:00:00Z");
  let ps = 0, es = 0;
  for (let i = 0; i < j.days; i++) {
    const m = new Date(d0.getTime() + i * 86400000).getUTCMonth();
    if (j.tmean[i] != null) { mt[m] += j.tmean[i]; n[m]++; }
    mp[m] += j.precip[i] || 0;
    me[m] += j.pet[i] || 0;
    ps += j.precip[i] || 0;
    es += j.pet[i] || 0;
  }
  for (let m = 0; m < 12; m++) mt[m] /= (n[m] || 1);
  return { j, d0, clim: { ai: ps / es, mt, mp, me, lows: null } };
}

// The nights before the date in question. In the plugin these come from the
// forecast window, which reaches 7 days back and 16 forward and therefore moves
// as the scene is scrubbed; here they come from the fixture's own year, matched
// by day-of-year and wrapped — without the wrap, any date past the fixture's
// last day read as no cold at all and the model looked broken when it was not.
export function lowsBefore(j, d0, date, n) {
  const key = (d) => String(d.getUTCMonth() + 1).padStart(2, "0") + "-"
                   + String(d.getUTCDate()).padStart(2, "0");
  const want = key(date);
  let end = -1;
  for (let i = 0; i < j.days; i++)
    if (key(new Date(d0.getTime() + i * 86400000)) === want) { end = i; break; }
  if (end < 0) return [];
  const out = [];
  for (let k = n; k >= 1; k--) {
    const i = ((end - k) % j.days + j.days) % j.days;
    if (j.tmin[i] != null) out.push(j.tmin[i]);
  }
  return out;
}

// What the vegetation at `place` is doing on `iso`.
export function stateOn(place, iso) {
  const date = new Date(iso + "T12:00:00Z");
  const { j, d0, clim } = climOf(place);
  clim.lows = lowsBefore(j, d0, date, extractNumber(SRC, "leafNights"));
  const doy = Math.floor((date - new Date(Date.UTC(date.getUTCFullYear(), 0, 0))) / 86400000);
  return R.vegetationState(j.lat, clim, dayLen(j.lat, doy),
                           dayLen(j.lat, doy) - dayLen(j.lat, doy - 1),
                           date.getUTCMonth());
}
