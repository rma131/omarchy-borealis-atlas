# Project context — Borealis Atlas

What the whole project shares: where things are, what the words mean, and the
conventions every change follows. Read after `AGENTS.md`, before any spec.

## What it is

An Omarchy (Quickshell) overlay plugin: a touchscreen sky and weather explorer
built on Marko Stankovic's Borealis aurora shader. It draws the real sky, weather
and terrain for a place, across 7 days back and 16 forward. Published on the
Omarchy plugin marketplace as `io.github.rma131.borealis-atlas`; installed by
`git clone`, so everything in this repository lands on every user's machine.

## Where the truth lives

| Question | Source of truth |
|---|---|
| What must it do? | `openspec/specs/<capability>/spec.md` |
| Why is it built this way? What was rejected? | `docs/design.md` |
| What is being changed right now? | `openspec/changes/<change-id>/` |
| What was changed before, and what was asked? | `openspec/changes/archive/` and git history |
| What rules must never break? | `AGENTS.md`, enforced by `scripts/lint-invariants.sh` |
| How is the shader binary trusted? | `docs/build-provenance.md` |
| What does it cost to run? | `docs/measurements.md` |

Specs say **what**, briefly, with scenarios. `design.md` says **why**, at length,
with measurements. A spec links to the design section; it never repeats it.

## Capabilities

| Capability | Covers |
|---|---|
| `data-integrity` | untrusted input, caching, rate limits, failure reporting |
| `sky-astronomy` | sun, moon, phases, eclipses |
| `weather` | forecast mapping, storms, warning tier |
| `location-time` | where and when: zones, search, suggestions, readout |
| `terrain-water` | skyline, snow and trees, water detection |
| `interaction` | keys, gestures, touch ownership |
| `globe` | the wireframe globe beside the place name |
| `shader-provenance` | reproducible shader, uniform and GLSL constraints |

A change touching several capabilities carries one delta spec per capability.
A new capability needs a reason not to fit an existing one.

## Map of the code

Everything is in one QML file plus the shader. Find things by **function name**,
never by line number — line numbers move with every edit.

| Area | Where |
|---|---|
| Validators | `boundedParse`, `finiteIn`, `numArray`, `strArray`, `capArray`, `validLoc`, `validFc`, `validTerrain` |
| Network | `curlCmd`, `classifyExit`, `noteExit`, `beginFetch`, `stale`, `topUp`, `heldBack`, the `*Proc` Processes |
| Sky | `resolveSky` (weather, storm, warning tier), `pushSky` (uniforms), `moonCompute` |
| Time and place | `tzShiftMs`, `nowAtLoc`, `midnightAtLoc`, `syncTimeOfDay`, `onLocChanged` |
| Search | `splitQuery`, `parseWhen`, `applyWhen`, `submitSearch`, `whenSuggestions`, `askSuggestions` |
| Terrain | `fetchHorizon` (pass 1), `fetchHorizonFan` (pass 2), `fetchNearField` (pass 3), `findWater`, `adoptWater`, `fetchMarine` |
| Cache | `saveCache`, `loadCache`, `terrain*` functions, `cacheWriteScript` |
| Shader | `shaders/aurora.frag`; uniform block `buf`; `upperScene`, `main` |
| Globe | `Globe.qml`, `coastline.js` |

## Glossary

- **tod** — time of day as days from the target's local midnight; unbounded, so
  1.5 is noon tomorrow. The shader wraps it.
- **target zone** — the UTC offset of the place being looked at, from the
  forecast reply. `tzStale` is true between a change of place and that reply.
- **pinned** — the user typed a moment; the sky holds still and the readout stays
  up until a touch.
- **notice** — the readout shown for six seconds after a change of place.
- **pass 1 / 2 / 3** — elevation sampling: ring (33 azimuths at 4, 11, 25 km),
  fan (the drawn skyline), near field (10 × 10 over ±6 km). Each is one request of
  at most 100 points.
- **ground / marine** — the source of a water verdict: the elevation test, or the
  marine model's wave heights. Ground outranks marine.
- **generation (`locGen`)** — increments on every real change of place; a reply
  stamped with an older one is discarded.
- **warning tier** — `sev.y`; storm severity at the thresholds national services
  use for warnings.

## External services

| Host | Used for | Notes |
|---|---|---|
| `api.open-meteo.com` | forecast, elevation | rate-limited; elevation ≤ 100 points per call |
| `archive-api.open-meteo.com` | a year of climate | |
| `geocoding-api.open-meteo.com` | search and suggestions | |
| `marine-api.open-meteo.com` | open water | multi-point reply is a JSON array |
| `services.swpc.noaa.gov` | Kp index | global, not place-dependent |
| `get.geojs.io`, `wttr.in` | IP location | only when no location is set |

All Open-Meteo hosts share one rate limit. Testing against them must be paced:
several sessions of this project have exhausted it.

## Conventions

- **Comments explain why**, in prose, often with the measurement that settled
  it. Match the surrounding density; do not strip them.
- **Commits**: a sentence-case title saying what changed for the user; a body
  saying why, what was tried, and what it cost. End with the attribution trailer
  the working agent is asked to use.
- **Change ids** are kebab-case and verb-led: `find-water-beyond-near-field`.
- **Verification kinds** on scenarios: `test` (tests/), `lint`
  (scripts/lint-invariants.sh), `ci` (GitHub Actions), `live` (checked by hand
  on a running shell — say how in the change's tasks).
