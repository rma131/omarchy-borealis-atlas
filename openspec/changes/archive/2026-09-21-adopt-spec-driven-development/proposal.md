# Proposal: Keep requests, specs and verification coherent across sessions and models

## Request

> "I want to implement a spec driven development framework for this project to
> keep it in order, llm agnostic and allow the context and documentation and
> requests to be consistent and coherent through time, other iterations and
> comprehensive. How can we do this?"
> — 2026-09-21

Decisions taken with the requester the same day: an OpenSpec-shaped layout
without installing the tool; the plugin repository first and the dotfiles
repository second; specs kept in the plugin repository.

## Intent

The plugin had grown through dozens of iterations and several agents. What it
must do was spread across `docs/design.md`, long commit messages and whatever an
agent remembered. Rules learned the hard way — append uniforms last, PlainText
on every Text, no curl `--retry`, restart the shell after QML edits, never type
into the user's session — existed only as prose or in one session's memory, so
each new session could break them again.

## Scope

In scope:
- `AGENTS.md` as the single, tool-independent entry point; `CLAUDE.md` imports it
- `openspec/` with specs for eight capabilities, backfilled from verified behaviour
- change templates, and this archived change as the first record
- `scripts/check.sh`: invariant lint, spec lint, logic tests, validator, shader
- logic tests that run the plugin's own functions against real fixtures
- a CI workflow running the gate

Out of scope:
- installing OpenSpec or Spec Kit, or generating per-tool command files
- behaviour changes to the plugin
- the dotfiles repository (a separate, second step)

## Approach

OpenSpec's model — `specs/` as current truth, `changes/` as deltas merged back on
archive — matches "coherent through time" directly, and its format is kept
exactly so the tool can be adopted later. Instead of slash commands, the workflow
is written in `AGENTS.md`, which any model can follow by reading a file. The
parts that must not depend on anyone reading anything are checks that fail.

## Capabilities affected

All eight capabilities are introduced as the baseline, written directly into
`openspec/specs/` rather than as ADDED deltas: they describe the plugin as it
already was, not a change to it.

## Risks

Specs that describe intended rather than actual behaviour. Mitigated by writing
them only from behaviour already verified, and by linking each `test` scenario to
a test that runs the real code.
