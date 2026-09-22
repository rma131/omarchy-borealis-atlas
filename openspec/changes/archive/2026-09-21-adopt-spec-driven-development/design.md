# Design: adopt-spec-driven-development

## Findings

- Neither OpenSpec nor Spec Kit is installed; `node` and `uvx` are.
- The plugin had no agent instructions at all. The dotfiles repository has a
  working agreement whose invariants are enforced by `lint-invariants.sh` — the
  pattern that works in practice here, and the one reused.
- The plugin is installed by `git clone`, so anything committed ships to users.

## Options considered

| Option | Result | Verdict |
|---|---|---|
| OpenSpec CLI (`@fission-ai/openspec`, Node ≥ 20.19) | living specs + deltas; generates command files for 30+ tools; commands already renamed once (`/opsx:`) | shape adopted, tool not |
| GitHub Spec Kit (`specify-cli`, Python 3.11 + uv) | constitution + per-feature spec/plan/tasks folders that accumulate | heavier; weaker at keeping one evolving truth |
| OpenSpec-shaped, driven by AGENTS.md | same layout and format, no dependency, no generated files | **chosen** |

## Decision

The format is OpenSpec's (`### Requirement:` / `#### Scenario:`, delta headings,
`archive/YYYY-MM-DD-<id>`), verified against its concepts document, with one
addition: each scenario ends `- VERIFIED: test | lint | ci | live`, and `test`
is checked both ways against test titles. That link is what keeps specs and
tests from drifting.

## Findings during implementation

- **A check nobody has seen fail is not trusted.** Every invariant and every spec
  rule was mutation-tested: each was broken on a copy and had to be caught. The
  first version of "JSON.parse only inside boundedParse" used a fixed line window
  and missed a JSON.parse in the very next function; it now measures the
  function's real extent by matching braces.
- Values built inside Node's `vm` sandbox carry that realm's prototypes, so strict
  deep-equality called identical results unequal. The harness clones at the
  boundary; no test was loosened to pass.
- Water fixtures record the sampling geometry they were taken with, and the tests
  rebuild offsets from the plugin's own constants, so changing the sampling fails
  the tests until the fixtures are refreshed rather than passing on stale data.
