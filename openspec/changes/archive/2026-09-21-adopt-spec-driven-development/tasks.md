# Tasks: adopt-spec-driven-development

## Implementation
- [x] 1.1 Confirm OpenSpec's current file format against its concepts document
- [x] 1.2 Capture elevation fixtures with the plugin's own sampling geometry (10 files, paced under the rate limit)
- [x] 1.3 `tests/extract.mjs` lifts pure functions from the QML; `tests/logic.test.mjs` runs 19 scenarios
- [x] 1.4 `scripts/lint-invariants.sh` — nine rules
- [x] 1.5 Specs for eight capabilities: 31 requirements, 51 scenarios
- [x] 1.6 `scripts/lint-specs.mjs` — OpenSpec structure plus two-way scenario ↔ test link
- [x] 1.7 `scripts/check.sh` as the single gate; `.github/workflows/check.yml`
- [x] 1.8 `AGENTS.md`, `CLAUDE.md` (imports it), `openspec/project.md`, templates
- [x] 1.9 Link from README and docs/development.md

## Verification
- [x] 2.1 `scripts/check.sh` passes: invariants, specs, 19 logic tests, validator, shader rebuild
- [x] 2.2 All nine invariant rules mutation-tested — each broken on a copy and caught (rule 2 initially missed; fixed)
- [x] 2.3 All eight spec-lint rules mutation-tested and caught
- [x] 2.4 No plugin behaviour changed: QML and shader untouched, validator passes

## Close
- [x] 3.1 Baseline specs written directly into openspec/specs/ (no deltas: nothing changed)
- [x] 3.2 Lasting findings recorded in this change's design.md
- [x] 3.3 Archived as 2026-09-21-adopt-spec-driven-development
