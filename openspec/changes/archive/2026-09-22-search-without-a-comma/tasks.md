# Tasks: search-without-a-comma

## Implementation
- [x] 1.1 `trailingWhen()` — the longest trailing moment that leaves a place
- [x] 1.2 `splitQuery` uses it, after testing the whole line as a moment
- [x] 1.3 `suggestSplit` uses the same rule, plus a last word beginning with a
      digit or a sign, so a half-typed time is not sent to the geocoder

## Verification
- [x] 2.1 `scripts/check.sh` passes
- [x] 2.2 New or changed `test` scenarios have tests titled "<capability>: <Scenario>"
- [x] 2.3 Live checks, each with how it was checked:
  - [x] full shell restart — `omarchy-restart-shell`, PID changed each run
  - [x] all six data paths load — forecast, Kp, ring, climate, horizon and
        water all read back from the cache at Quito
  - [x] `Montreal 14:00` typed with no separator — readout came back
        "14:00 · Clear · 15° · Tuesday 22 September · Montreal · Canada"
  - [x] "Quito su" offered sunrise / sunset / sunday, and taking sunset landed
        on "18:09 GMT-5 · Showers · 13° · Quito · Ecuador", in Quito's own zone
  - [x] "Istanb" still lists places — Istanbul, Istanbuul (Somalia, three of
        them), Istanbulbogazi — so the place path is untouched
  - [x] the hint under the box now reads "Istanbul tomorrow 15:00" rather than
        teaching a separator that is no longer needed
- [x] 2.4 If the shader changed: recompiled, digests updated in docs/build-provenance.md
      (n/a — no shader change)

## Close
- [x] 3.1 Delta specs merged into openspec/specs/
- [x] 3.2 Lasting findings moved from design.md into docs/design.md
- [x] 3.3 Change moved to openspec/changes/archive/<YYYY-MM-DD>-<change-id>/
