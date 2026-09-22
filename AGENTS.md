# Working on Borealis Atlas

Instructions for anyone changing this repository — a person, or an agent built on
any model. This file is the single entry point; nothing here depends on a
particular tool, and nothing outside the repository is needed to follow it.

## Read first, in this order

1. **This file.** The workflow, the rules that must not break, and the definition
   of done.
2. **`openspec/project.md`** — the map of the code, the glossary, the services.
3. **The spec for what you are touching** — `openspec/specs/<capability>/spec.md`.
   These are the current truth about what the plugin does.
4. **The matching section of `docs/design.md`** — why it is built that way and
   what was already tried and rejected. Do not re-propose something it rejects
   without new evidence.

## How a change is made

Every change that alters behaviour goes through a change folder. It is how the
request, the reasoning and the verification survive the session that produced
them — the next person or model starts from the record, not from memory.

1. **Record the request.** Create `openspec/changes/<change-id>/proposal.md` from
   `openspec/templates/proposal.md`, quoting the request **verbatim** with its
   date. Change ids are kebab-case and verb-led.
2. **Investigate before designing.** Reproduce the problem and measure it. Put
   findings, options and the decision in `design.md`.
3. **Write the delta spec** in `openspec/changes/<change-id>/specs/<capability>/spec.md`
   using `openspec/templates/spec-delta.md`: ADDED / MODIFIED / REMOVED / RENAMED
   requirements, each with scenarios and a `- VERIFIED:` line.
4. **List the tasks** in `tasks.md` from the template, including how each live
   check will be done.
5. **Implement**, and add a test titled `"<capability>: <Scenario>"` for every
   scenario marked `VERIFIED: test`.
6. **Verify**: `scripts/check.sh` passes, and every live check in `tasks.md` is
   ticked with what was observed.
7. **Archive**: merge the deltas into `openspec/specs/`, move lasting findings
   into `docs/design.md`, move the folder to
   `openspec/changes/archive/<YYYY-MM-DD>-<change-id>/`, and commit.

**No change folder needed** for typos, comment or doc wording, or a fix that
restores behaviour a spec already states. Say which in the commit message.

**If an approved plan turns out to be wrong**, stop and say so. Record it under
"Corrections" in `design.md` — what was believed, what was measured, what
replaced it. Never quietly implement something other than what was agreed.

## Rules that must not break

Each is enforced by `scripts/lint-invariants.sh`, and each exists because
breaking it once cost real time. If a change seems to need breaking one, the
change is wrong — stop and ask.

| Rule | Why |
|---|---|
| Every `Text` has `textFormat: Text.PlainText` | names and conditions come from third parties; AutoText would render their markup |
| `JSON.parse` only inside `boundedParse` | it is the one place replies are size-capped and shape-checked |
| curl is never given `--retry` | curl retries HTTP 429, answering a rate limit with more requests |
| No `const` arrays in the shader | they compile, then blank the overlay on the GLSL 120 target (C7516) |
| Uniform members are appended **last** | inserting one shifts std140 offsets; later members are silently never written |
| Elevation requests carry ≤ 100 points | the service rejects 101 with HTTP 400 |
| Network Processes declare `src`, `stderr`, `onExited` | otherwise a dead network and a bad reply are indistinguishable |
| `docs/build-provenance.md` records the shipped shader digests | the binary must be provably built from source |
| The QML fallback id matches `manifest.json` | the id is also the install directory name |

Also true, and not mechanically checkable:

- **Every remote reply and the cache file are untrusted.** Validate each element
  with the existing helpers (`finiteIn`, `numArray`, `validLoc`, …); one bad
  element rejects the whole series.
- **Never render curl's stderr.** It echoes the request URL back.
- **Water-detection gates are fixed** (`n ≥ 4`, isolation ≥ 1.5, rank ≤ 1).
  Loosening them to admit one place admits farmland everywhere; see
  `terrain-water`.

## Operating on a live machine

These apply when you can run commands on the machine the plugin is installed on.

- **QML changes need a full shell restart.** Hot-reload logs "reloading" but does
  not rebuild the overlay. Restart, then confirm the shell's PID changed.
- **Verify all six data paths**, not just that the scene draws: forecast, Kp,
  ring, climate, horizon, water. A broken validator draws a perfectly nice scene
  with no data in it.
- **Pace the weather services.** All Open-Meteo hosts share one rate limit and
  testing has exhausted it more than once. Space requests out; wait out a 429
  rather than retrying into it.
- **Never inject keystrokes or clicks unless the overlay is confirmed open and
  focused** (check the `borealis` layer exists first). Synthetic input sent at the
  wrong moment lands in the person's own terminal.
- **Never trigger a real screen lock** to test; it locks the person out. If a
  test changes idle or lock timings, restore them immediately and say so.
- **Ask before anything outward-facing**: pushing, opening issues, submitting to
  the marketplace.

## Publishing

- The repository is **public and installed by `git clone`**: everything
  committed lands on every user's machine. Keep it small; no personal data, no
  secrets, nothing generated per machine.
- **Marketplace updates** go through a new `[Verify]` issue on
  `omacom/omarchy-plugin-marketplace` ("Verify and publish a newer upstream
  commit") with the full commit SHA — never by editing the original submission.
  Lead the change summary with the security surface. If a pending update is about
  to be overtaken by a newer commit, supersede it rather than stack two.
- Commits that touch `.github/workflows/` must be pushed over SSH; the `gh` token
  in use lacks the `workflow` scope.

## Definition of done

- `scripts/check.sh` exits 0.
- Every scenario the change adds or modifies is verified the way it says.
- Live checks in `tasks.md` are ticked with what was actually seen.
- The change is archived and its deltas merged, so `openspec/specs/` describes
  the plugin as it now is.
- The commit message says what changed for the user and why.
