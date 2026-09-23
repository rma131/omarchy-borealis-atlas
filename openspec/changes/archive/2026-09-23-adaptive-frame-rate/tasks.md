# Tasks: adaptive-frame-rate

## Implementation
- [x] 1.1 `frameMsFor(lively, fastSky)` — a pure rule: 16 ms touched, 33 ms with
      rain or a storm, 100 ms on a calm drifting sky
- [x] 1.2 `lively`, `fastSky` and `paced` derived from state the scene already
      keeps; `driftAllowed` lifted out of the drift timer so both clocks ask the
      same question
- [x] 1.3 One paced `Timer` advances the shader clock and the drift together,
      running only in the reduced-cost mode
- [x] 1.4 The declarative `NumberAnimation on time` runs only when not paced
- [x] 1.5 `Behavior on tod` disabled while drifting under the paced clock, so a
      step is the frame rather than being smoothed back into sixty of them

## Verification
- [x] 2.1 `scripts/check.sh` passes
- [x] 2.2 New or changed `test` scenarios have tests titled "<capability>: <Scenario>"
- [x] 2.3 Live checks, each with how it was checked:
  - [x] full shell restart — `omarchy-restart-shell`, PID changed each run
  - [x] all six data paths load — Montreal and then Quito, both complete
  - [x] a calm sky costs almost nothing — **8.76 W, GPU 354 MHz** over 50 s,
        against 301 MHz dismissed and 589 MHz at the old sixty
  - [x] touching brings the frames back — 363 MHz idle, **658 MHz** with the
        search open, 392 MHz after dismissing it
  - [x] the middle rate engages on its own — Quito showing Drizzle sat at
        **509 MHz**, between the calm and the touched readings
  - [x] mains is untouched — `paced` is false there, the `NumberAnimation`
        runs and the paced timer does not
- [x] 2.4 If the shader changed: recompiled, digests updated (n/a — no shader change)

## Close
- [x] 3.1 Delta specs merged into openspec/specs/
- [x] 3.2 Lasting findings moved from design.md into docs/design.md
- [x] 3.3 Change moved to openspec/changes/archive/<YYYY-MM-DD>-<change-id>/
