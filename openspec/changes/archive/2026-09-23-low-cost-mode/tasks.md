# Tasks: low-cost-mode

## Implementation
- [x] 1.1 `vec4 qual` appended last in the uniform block
- [x] 1.2 `upperScene()` gains a `cheap` switch: no starfield motion blur, no
      third curtain, no meteors — used only for the copies the water is made of
- [x] 1.3 Reflection taps 5 → 3 when cheap, with the outer pair's weight handed
      back so the water does not darken
- [x] 1.4 The third rain layer is skipped when there is no storm, in every mode
- [x] 1.5 `UPower.onBattery` drives `quality`, and `quality` drives `renderScale`
- [x] 1.6 `layer.enabled` / `layer.textureSize` at 60 % on battery, off on mains
- [x] 1.7 `resolution` follows the render target, not the screen

## Verification
- [x] 2.1 `scripts/check.sh` passes
- [x] 2.2 New or changed `test` scenarios have tests titled "<capability>: <Scenario>"
- [x] 2.3 Live checks, each with how it was checked:
  - [x] full shell restart — `omarchy-restart-shell`, PID changed each run
  - [x] all six data paths load — Toronto, water kind 2 (lake) read back from
        the cache with forecast, Kp, ring, climate and horizon alongside
  - [x] re-measured in the form of docs/measurements.md — 302 MHz dismissed
        (August: 301), 1021 MHz full, 688 MHz battery mode, table in design.md
  - [x] the cheaper scene still reads — sky, sun, lake glitter, treeline, text
        and globe all correct; crowns softer, silhouette and turned colour intact
  - [x] mains is unchanged — 1013 MHz on the real UPower path against 1021 before
  - [x] the switch on unplugging — verified 2026-09-23 with the machine
        actually unplugged: UPower reported battery, the scene came up in the
        cheap mode with no input, and the treeline was visibly softer while the
        readout and globe stayed crisp
  - [x] re-measured in watts, which is what the cost actually is:
        **6.62 W idle · 10.73 W battery mode · 18.22 W full** on a 45.2 Wh cell,
        so the overlay's own draw falls from +11.60 W to +4.11 W — a 65 % cut,
        and 2.5 h of runtime becomes 4.2 h
- [x] 2.4 If the shader changed: recompiled, digests updated in docs/build-provenance.md

## Close
- [x] 3.1 Delta specs merged into openspec/specs/
- [x] 3.2 Lasting findings moved from design.md into docs/design.md
- [x] 3.3 Change moved to openspec/changes/archive/<YYYY-MM-DD>-<change-id>/
