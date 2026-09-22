# Tasks: follow-the-growing-season

## Implementation
- [x] 1.1 `fetchClimate()` requests `temperature_2m_mean` and `temperature_2m_min`
- [x] 1.2 `climProc` keeps a monthly profile and the last nights, with the day
      they end on, instead of collapsing the year to one number
- [x] 1.3 `fetchForecast()` requests `temperature_2m_min`; `parseDaylight()`
      keeps the window's nights and the day it opens on
- [x] 1.4 `seasonLows()` joins the archive's nights to the window's, without
      counting the overlap twice
- [x] 1.5 `vegetationState()` — canopy, turn, evergreen, browning, and the four
      form weights
- [x] 1.6 `validClimate()` rebuilds a cached climatology; both cache paths use it
- [x] 1.7 `pushSky()` resolves the season for the day on screen and writes
      `veg` and `flora`
- [x] 1.8 Shader: `vec4 veg` and `vec4 flora` appended last in the uniform block
- [x] 1.9 Shader: form — ground cover above the treeline, flat crown, column,
      rosette drum, and bare branches that keep their silhouette
- [x] 1.10 Shader: colour — the turn through the existing canopy mask, the dry
      season on the ground, litter in the foreground turf
- [x] 1.11 Two thresholds, not one: a canopy is put out when the month can grow
      it and held until the month is near freezing
- [x] 1.12 A cached climate or forecast written before the season existed is
      refetched rather than kept forever (`climateThin`, and no cached forecast
      without its nights)

## Verification
- [x] 2.1 `scripts/check.sh` passes
- [x] 2.2 New or changed `test` scenarios have tests titled "<capability>: <Scenario>"
- [x] 2.3 Live checks, each with how it was checked:
  - [x] full shell restart — `omarchy-restart-shell`, PID 1260 → 127169
  - [x] all six data paths load — read back from
        `~/.local/state/omarchy/borealis-sky.json`: fc (tmin 23, d0 2026-09-15),
        kp, ring, climate (mt 12, lowsEnd 2026-09-15), horizon, water
  - [x] Montreal shows early colour on the ridge, tree by tree — 22 September
        14:00, scattered amber crowns among green ones, autumn 0.506
  - [x] scrubbing forward deepens it — `/7 oct 14:00`, autumn 0.799, visibly
        more crowns turned and deeper in colour
  - [x] Quito's ground above the treeline is cover, not grey rock — `/Quito,
        14:00`, the high ridge is olive paramo with blunt rosette crowns while
        the lower ridge keeps its pointed conifers
- [x] 2.4 If the shader changed: recompiled, digests updated in docs/build-provenance.md

## Close
- [x] 3.1 Delta specs merged into openspec/specs/
- [x] 3.2 Lasting findings moved from design.md into docs/design.md
- [x] 3.3 Change moved to openspec/changes/archive/<YYYY-MM-DD>-<change-id>/
