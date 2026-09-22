#!/usr/bin/env node
// lint-specs.mjs — keep the specs well-formed and honest.
//
// Structure follows OpenSpec (openspec/specs/<capability>/spec.md with
// "### Requirement:" and "#### Scenario:"), so the tool can be adopted later
// without a migration. One addition: every scenario ends with
//
//     - VERIFIED: test | lint | ci | live
//
// saying how it is actually known to hold. "test" is checked both ways — the
// scenario must have a test titled "<capability>: <Scenario>", and every such
// test must point at a scenario that still exists and still says "test". That
// link is what stops specs and tests drifting apart quietly.

import { readFileSync, readdirSync, existsSync, statSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const SPECS = join(ROOT, "openspec/specs");
const CHANGES = join(ROOT, "openspec/changes");
const TESTS = join(ROOT, "tests");
const KINDS = new Set(["test", "lint", "ci", "live"]);
const DELTA = new Set(["ADDED Requirements", "MODIFIED Requirements",
                       "REMOVED Requirements", "RENAMED Requirements"]);

const errors = [];
const err = (where, msg) => errors.push(`${where}: ${msg}`);
const dirs = (p) => existsSync(p) ? readdirSync(p).filter((d) => statSync(join(p, d)).isDirectory()) : [];

// ---- current specs ----------------------------------------------------------
const scenarios = new Map();          // "cap: Name" -> kind
let nReq = 0;
for (const cap of dirs(SPECS)) {
  const file = join(SPECS, cap, "spec.md");
  const where = `openspec/specs/${cap}/spec.md`;
  if (!existsSync(file)) { err(where, "missing"); continue; }
  const lines = readFileSync(file, "utf8").split("\n");
  if (!/^# \S/.test(lines[0])) err(where, "first line must be a '# <Title>' heading");
  if (!lines.includes("## Purpose")) err(where, "no '## Purpose' section");
  if (!lines.includes("## Requirements")) err(where, "no '## Requirements' section");

  let req = null, scen = null;
  const closeScenario = () => {
    if (!scen) return;
    const b = scen.body;
    if (!b.some((l) => /^- WHEN /.test(l))) err(where, `scenario "${scen.name}" has no '- WHEN'`);
    if (!b.some((l) => /^- THEN /.test(l))) err(where, `scenario "${scen.name}" has no '- THEN'`);
    const v = b.filter((l) => /^- VERIFIED:/.test(l));
    if (v.length !== 1) err(where, `scenario "${scen.name}" needs exactly one '- VERIFIED: test|lint|ci|live'`);
    else {
      const kind = v[0].replace(/^- VERIFIED:\s*/, "").trim();
      if (!KINDS.has(kind)) err(where, `scenario "${scen.name}": unknown verification '${kind}'`);
      const key = `${cap}: ${scen.name}`;
      if (scenarios.has(key)) err(where, `duplicate scenario "${scen.name}"`);
      scenarios.set(key, kind);
    }
    scen = null;
  };
  const closeRequirement = () => {
    closeScenario();
    if (!req) return;
    if (!/\b(SHALL|MUST)\b/.test(req.text)) err(where, `requirement "${req.name}" states no SHALL or MUST`);
    if (req.scenarios === 0) err(where, `requirement "${req.name}" has no scenario`);
    req = null;
  };
  for (const line of lines) {
    let m;
    if ((m = line.match(/^### Requirement: (.+)$/))) { closeRequirement(); req = { name: m[1], text: "", scenarios: 0 }; nReq++; }
    else if ((m = line.match(/^#### Scenario: (.+)$/))) {
      closeScenario();
      if (!req) err(where, `scenario "${m[1]}" outside a requirement`);
      else req.scenarios++;
      scen = { name: m[1], body: [] };
    } else if (/^#{1,3} /.test(line)) closeRequirement();
    else if (scen) { if (line.trim()) scen.body.push(line.trim()); }
    else if (req) req.text += " " + line;
  }
  closeRequirement();
}

// ---- tests <-> scenarios ----------------------------------------------------
const tested = new Set();
for (const f of existsSync(TESTS) ? readdirSync(TESTS).filter((f) => f.endsWith(".test.mjs")) : []) {
  const src = readFileSync(join(TESTS, f), "utf8");
  for (const m of src.matchAll(/\btest\(\s*"([^"]+)"/g)) {
    const title = m[1];
    tested.add(title);
    if (!scenarios.has(title)) err(`tests/${f}`, `"${title}" names no scenario in openspec/specs`);
    else if (scenarios.get(title) !== "test") err(`tests/${f}`, `"${title}" tests a scenario marked VERIFIED: ${scenarios.get(title)}`);
  }
}
for (const [key, kind] of scenarios)
  if (kind === "test" && !tested.has(key)) err("openspec/specs", `"${key}" says VERIFIED: test but no test has that title`);

// ---- changes ----------------------------------------------------------------
const checkChange = (dir, where, archived) => {
  for (const f of ["proposal.md", "tasks.md"])
    if (!existsSync(join(dir, f))) err(where, `missing ${f}`);
  if (archived && existsSync(join(dir, "tasks.md")) && /^\s*- \[ \]/m.test(readFileSync(join(dir, "tasks.md"), "utf8")))
    err(where, "archived with unchecked tasks");
  for (const cap of dirs(join(dir, "specs"))) {
    const file = join(dir, "specs", cap, "spec.md");
    if (!existsSync(file)) continue;
    for (const line of readFileSync(file, "utf8").split("\n")) {
      const m = line.match(/^## (.+)$/);
      if (m && !DELTA.has(m[1])) err(`${where}/specs/${cap}/spec.md`, `'## ${m[1]}' is not a delta heading (ADDED/MODIFIED/REMOVED/RENAMED Requirements)`);
    }
  }
};
let nChanges = 0, nArchived = 0;
for (const id of dirs(CHANGES).filter((d) => d !== "archive")) { nChanges++; checkChange(join(CHANGES, id), `openspec/changes/${id}`, false); }
for (const id of dirs(join(CHANGES, "archive"))) {
  nArchived++;
  if (!/^\d{4}-\d{2}-\d{2}-[a-z0-9-]+$/.test(id)) err(`openspec/changes/archive/${id}`, "archived name must be YYYY-MM-DD-<change-id>");
  checkChange(join(CHANGES, "archive", id), `openspec/changes/archive/${id}`, true);
}

// ---- report -----------------------------------------------------------------
const byKind = {};
for (const k of scenarios.values()) byKind[k] = (byKind[k] || 0) + 1;
if (errors.length) {
  for (const e of errors) console.log(`\x1b[1;31m✗\x1b[0m ${e}`);
  process.exit(1);
}
console.log(`\x1b[1;32m✓\x1b[0m specs: ${dirs(SPECS).length} capabilities, ${nReq} requirements, ` +
            `${scenarios.size} scenarios (${Object.entries(byKind).map(([k, n]) => `${n} ${k}`).join(", ")}); ` +
            `${nChanges} open changes, ${nArchived} archived`);
