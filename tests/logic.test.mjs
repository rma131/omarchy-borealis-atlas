// Executable scenarios. Every test title is "<capability>: <Scenario heading>",
// matching a `#### Scenario:` in openspec/specs/<capability>/spec.md exactly —
// scripts/check.sh fails if a title names a scenario that does not exist, so a
// spec change cannot silently orphan its test.
//
// Run: node --test tests/     (no dependencies; Node 20+)

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { load, extractArray, extractNumber, QML_PATH } from "./extract.mjs";

const QML = readFileSync(QML_PATH, "utf8");

// ---- data-integrity ---------------------------------------------------------
const V = load(["capStr", "finiteIn", "capArray", "numArray", "strArray",
                "validLoc", "boundedParse", "classifyExit"],
               { maxStrLen: extractNumber(QML, "maxStrLen") }).root;

test("data-integrity: Non-finite numbers are rejected", () => {
  assert.equal(V.finiteIn(NaN, -90, 90), null);
  assert.equal(V.finiteIn(Infinity, -90, 90), null);
  assert.equal(V.finiteIn("12.5", -90, 90), 12.5);
  assert.equal(V.finiteIn(91, -90, 90), null);
});

test("data-integrity: One bad element rejects the whole series", () => {
  assert.equal(V.numArray([1, 2, "3"], 10, 0, 10, false), null);
  assert.equal(V.numArray([1, null, 3], 10, 0, 10, false), null);
  assert.deepEqual(V.numArray([1, null, 3], 10, 0, 10, true), [1, null, 3]);
  assert.equal(V.numArray([1, 2, 3], 2, 0, 10, false), null, "too long is malformed");
});

test("data-integrity: Oversized or non-object replies parse to nothing", () => {
  assert.equal(V.boundedParse("", 100), null);
  assert.equal(V.boundedParse("{\"a\":1}", 3), null);
  assert.equal(V.boundedParse("42", 100), null);
  assert.equal(V.boundedParse("{not json", 100), null);
  assert.deepEqual(V.boundedParse("{\"a\":1}", 100), { a: 1 });
});

test("data-integrity: Locations are canonicalised before use", () => {
  assert.equal(V.validLoc({ lat: 200, lon: 0 }), null);
  assert.equal(V.validLoc({ latitude: "x", longitude: 1 }), null);
  const long = "x".repeat(500);
  const l = V.validLoc({ latitude: 45.5, longitude: -73.6, name: long });
  assert.equal(l.lat, 45.5);
  assert.ok(l.name.length <= extractNumber(QML, "maxStrLen"));
});

test("data-integrity: A failed fetch says whether it was the network or the service", () => {
  assert.equal(V.classifyExit(0, ""), "ok");
  assert.equal(V.classifyExit(6, "Could not resolve host"), "offline");
  assert.equal(V.classifyExit(7, ""), "offline");
  assert.equal(V.classifyExit(28, ""), "timeout");
  assert.equal(V.classifyExit(22, "curl: (22) The requested URL returned error: 429"), "ratelimit");
  assert.equal(V.classifyExit(22, "curl: (22) The requested URL returned error: 503"), "server");
  assert.equal(V.classifyExit(22, "curl: (22) The requested URL returned error: 404"), "badrequest");
  assert.equal(V.classifyExit(63, ""), "toobig");
});

// ---- sky-astronomy ----------------------------------------------------------
const M = load(["moonName", "moonCompute"],
               { tzShiftMs: () => 0, moonSunMean: extractNumber(QML, "moonSunMean") }).root;
const moonAt = (iso) => M.moonCompute(new Date(iso));

test("sky-astronomy: Every eclipse from 2026 to 2028 lands on its day with the right kind", () => {
  const cases = [
    ["2026-02-17T12:01Z", "Annular solar eclipse"],
    ["2026-03-03T11:38Z", "Total lunar eclipse"],
    ["2026-08-12T17:37Z", "Total solar eclipse"],
    ["2026-08-28T04:19Z", "Partial lunar eclipse"],
    ["2027-02-06T15:56Z", "Annular solar eclipse"],
    ["2027-08-02T10:06Z", "Total solar eclipse"],
    ["2028-07-22T02:56Z", "Total solar eclipse"],
    ["2028-12-31T16:52Z", "Total lunar eclipse"],
  ];
  for (const [iso, kind] of cases) assert.equal(moonAt(iso).eventName, kind, iso);
});

test("sky-astronomy: New and full moons off the node pass without an eclipse", () => {
  for (const iso of ["2026-05-16T20:01Z", "2026-10-10T15:50Z", "2026-09-26T16:49Z",
                     "2027-02-20T23:14Z" /* penumbral: invisible, so nothing */]) {
    assert.doesNotMatch(moonAt(iso).eventName, /eclipse/i, iso);
  }
});

test("sky-astronomy: Phase is right to within minutes", () => {
  const p = moonAt("2026-08-12T17:37Z").phase;       // a real new moon
  const hours = Math.min(p, 1 - p) * 29.530588853 * 24;
  assert.ok(hours < 0.5, `new moon off by ${hours.toFixed(2)} h`);
});

// ---- location-time ----------------------------------------------------------
const midnight = () => new Date(2026, 8, 3, 0, 0, 0, 0);    // Thursday 3 September
const T = load(["looksTemporal", "daysUntilWeekday", "daysUntilDate", "parseWhen",
                "splitQuery", "whenSuggestions"], {
  midnightAtLoc: midnight,
  monthAbbr: extractArray(QML, "monthAbbr"),
  weekdayAbbr: extractArray(QML, "weekdayAbbr"),
  weekdayFull: extractArray(QML, "weekdayFull"),
  plainMoments: extractArray(QML, "plainMoments"),
}).root;

test("location-time: A place and a moment are told apart", () => {
  const q = T.splitQuery("Istanbul @ tomorrow 15:00");
  assert.equal(q.place, "Istanbul");
  const w = T.parseWhen(q.when);
  assert.equal(w.day, 1);
  assert.ok(Math.abs(w.frac - 15 / 24) < 1e-9);
  assert.deepEqual(T.splitQuery("Quito, 12 Sep"), { place: "Quito", when: "12 Sep" });
  assert.equal(T.parseWhen("12 sep 14:00").day, 9);
  assert.equal(T.parseWhen("friday 3pm").day, 1);
  assert.equal(T.parseWhen("sunset").solar, "set");
  assert.equal(T.parseWhen("+3").day, 3);
});

test("location-time: Place names that look like dates stay places", () => {
  for (const q of ["March", "Sunday", "New York", "banana", "3"]) {
    assert.equal(T.splitQuery(q).place, q, q);
    assert.equal(T.splitQuery(q).when, "", q);
  }
});

test("location-time: A moment it cannot read is refused whole", () => {
  assert.equal(T.parseWhen("banana"), null);
  assert.equal(T.parseWhen("tomorrow banana"), null);
  assert.equal(T.parseWhen("sep"), null, "a month with no day is not a date");
});

test("location-time: Suggested moments are always ones the search accepts", () => {
  assert.deepEqual(T.whenSuggestions("sun").map((s) => s.text), ["sunrise", "sunset", "sunday"]);
  for (const w of ["", "to", "s", "+", "3", "fri"])
    for (const s of T.whenSuggestions(w)) assert.ok(T.parseWhen(s.text), `${w} → ${s.text}`);
});

// ---- terrain-water ----------------------------------------------------------
// Rebuilt with the plugin's own constants, and checked against the geometry each
// fixture was sampled with: change the sampling and these fail until the
// fixtures are refreshed, rather than passing against data from another layout.
const W = load(["findWater", "adoptWater"]).root;
const hzRings = extractArray(QML, "hzRings"), hzAz = extractNumber(QML, "hzAz");
const nearN = extractNumber(QML, "nearN"), nearHalf = extractNumber(QML, "nearHalf");
const FIX = new URL("./fixtures/elevation/", import.meta.url);
const fixture = (name) => JSON.parse(readFileSync(new URL(name, FIX), "utf8"));

function ringVerdict(place) {
  const f = fixture(`${place}-ring.json`);
  assert.deepEqual(f.geometry, { hzRings, hzAz }, "ring fixture geometry is stale");
  const dx = [], dy = [], e = [];
  let k = 1;                                         // index 0 is the centre point
  for (let a = 0; a < hzAz; a++) {
    const ra = 2 * Math.PI * a / hzAz;
    for (const r of hzRings) { dx.push(r * Math.sin(ra)); dy.push(r * Math.cos(ra)); e.push(f.elevation[k++]); }
  }
  const area = Math.PI * 25000 * 25000;
  return W.findWater(dx, dy, e, area, area / (hzAz * hzRings.length));
}

function nearVerdict(place) {
  const f = fixture(`${place}-near.json`);
  assert.deepEqual(f.geometry, { nearN, nearHalf }, "near fixture geometry is stale");
  const dx = [], dy = [], step = 2 * nearHalf / (nearN - 1);
  for (let i = 0; i < nearN; i++)
    for (let j = 0; j < nearN; j++) {
      dy.push(nearHalf - 2 * nearHalf * i / (nearN - 1));
      dx.push(-nearHalf + 2 * nearHalf * j / (nearN - 1));
    }
  return W.findWater(dx, dy, f.elevation, 4 * nearHalf * nearHalf, step * step);
}

const KIND = { 1: "river", 2: "lake", 3: "sea" };

test("terrain-water: A lake beyond the near field is found in the wider pass", () => {
  assert.equal(nearVerdict("toronto"), null, "near field alone misses Lake Ontario — why pass 1 is used");
  const w = ringVerdict("toronto");
  assert.equal(KIND[w.kind], "lake");
  assert.equal(w.level, 74);
});

test("terrain-water: A river close by is found in the near field", () => {
  const w = nearVerdict("montreal");
  assert.equal(KIND[w.kind], "river");
  assert.equal(w.level, 4);
});

test("terrain-water: Flat farmland is not water", () => {
  assert.equal(ringVerdict("kansas"), null);
  assert.equal(nearVerdict("kansas"), null);
});

test("terrain-water: Mountains with no water stay dry", () => {
  assert.equal(ringVerdict("quito"), null);
  assert.equal(nearVerdict("quito"), null);
});

test("terrain-water: Below-sea-level polder is not taken for water", () => {
  // Amsterdam's water is real but invisible to the elevation test; what repeats
  // there is drained polder. The marine probe is what finds its sea.
  assert.equal(ringVerdict("amsterdam"), null);
  assert.equal(nearVerdict("amsterdam"), null);
});

test("terrain-water: The ground's verdict outranks the marine probe", () => {
  W.water = null;
  W.adoptWater({ kind: 2, level: 74, dist: 25000, src: "ground" });
  W.adoptWater({ kind: 3, level: 0, dist: 4000, src: "marine" });
  assert.equal(W.water.src, "ground", "a nearer marine cell must not overrule a measured lake");
  W.water = { kind: 0 };
  W.adoptWater({ kind: 3, level: 0, dist: 4667, src: "marine" });
  assert.equal(W.water.src, "marine", "marine fills in where the ground found nothing");
  W.adoptWater({ kind: 1, level: 4, dist: 900, src: "ground" });
  assert.equal(W.water.kind, 1);
});

// Every fixture on disk is exercised by some test above; one left over means a
// scenario was deleted without its data, or data was added without a scenario.
test("terrain-water: Fixtures and scenarios stay in step", () => {
  const used = new Set(["toronto", "montreal", "kansas", "quito", "amsterdam"]);
  for (const f of readdirSync(FIX)) assert.ok(used.has(f.split("-")[0]), `unused fixture ${f}`);
});
