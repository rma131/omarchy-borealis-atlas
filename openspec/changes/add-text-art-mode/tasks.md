# Tasks: add-text-art-mode

## Implementation
- [x] 1.1 `txt`, `ink0`, `ink1`, `ink2` appended last in the uniform block
- [x] 1.2 One coordinate snap at the top of `main()`; `pxuv` keeps the real pixel
- [x] 1.3 `cls` set where the scene already knows which region answered
- [x] 1.4 Array-free ordered dither: GLSL 120 has no bitwise operators either
- [x] 1.5 The dot as a disc inside a cell with a margin, area tracking brightness
- [x] 1.6 Tree count reduced in text mode so the ridge does not moire
- [x] 1.7 `gridFor`, `inkWeights`, `inkPivot`, `inkFor` — all pure, all tested
- [x] 1.8 `textArt` read from shell.json the way `palette` is, own-property check

## Verification
- [x] 2.1 `scripts/check.sh` passes
- [x] 2.2 New `test` scenarios have tests titled "<capability>: <Scenario>"
- [x] 2.3 Live checks, each with how it was checked:
  - [x] full shell restart — `omarchy-restart-shell`, shader cache cleared
  - [x] all six data paths load — Montreal, complete
  - [x] the scene reads as braille — cells legible as a grid, dots resolving
  - [x] four times of day are distinct — dawn amber on purple, noon pale cloud
        on blue, dusk with the sun as an accent disc, midnight aurora in cyan
  - [x] readout, globe and strip stay sharp — they are QML over the shader
  - [x] off by default — with no `textArt` key the column count is zero
- [x] 2.4 Shader recompiled, digests updated in docs/build-provenance.md

## Close
- [x] 3.1 Delta specs merged into openspec/specs/
- [ ] 3.2 Lasting findings moved from design.md into docs/design.md
- [ ] 3.3 Change moved to openspec/changes/archive/<YYYY-MM-DD>-<change-id>/
      **Held open deliberately: this lives on `feature/text-art` and is not
      merged. It archives if and when it ships.**
