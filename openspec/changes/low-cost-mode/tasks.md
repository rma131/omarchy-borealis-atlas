# Tasks: <change-id>

## Implementation
- [ ] 1.1 ...

## Verification
- [ ] 2.1 `scripts/check.sh` passes
- [ ] 2.2 New or changed `test` scenarios have tests titled "<capability>: <Scenario>"
- [ ] 2.3 Live checks, each with how it was checked:
  - [ ] full shell restart (QML is not picked up by hot-reload)
  - [ ] all six data paths load: forecast, Kp, ring, climate, horizon, water
  - [ ] ...
- [ ] 2.4 If the shader changed: recompiled, digests updated in docs/build-provenance.md

## Close
- [ ] 3.1 Delta specs merged into openspec/specs/
- [ ] 3.2 Lasting findings moved from design.md into docs/design.md
- [ ] 3.3 Change moved to openspec/changes/archive/<YYYY-MM-DD>-<change-id>/
