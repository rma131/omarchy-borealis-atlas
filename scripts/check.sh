#!/usr/bin/env bash
#
# check.sh — the one gate. Run it before every commit; CI runs it on every push.
#
# It is deliberately the same command for a person and for any agent, whatever
# model is behind it: "done" means this exits 0, not that something looked right.
#
#   1. invariants   rules learned the hard way        scripts/lint-invariants.sh
#   2. specs        OpenSpec structure, and every      scripts/lint-specs.mjs
#                   test tied to a scenario
#   3. logic        the pure functions of the plugin,  tests/logic.test.mjs
#                   run against real fixtures
#   4. manifest     Omarchy's own plugin validator     (when installed)
#   5. shader       rebuild and compare the digest     (when qsb is installed)
#
# Steps 4 and 5 need Omarchy and Qt tooling, so they are skipped — and say so —
# where those are absent. CI covers step 5 in shader-provenance.yml.
#
# Usage: scripts/check.sh [base-ref]     base-ref defaults to HEAD

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
BASE=${1:-HEAD}
failed=()

step() { printf '\n\033[1m── %s\033[0m\n' "$1"; }
skip() { printf '\033[1;34m–\033[0m %s\n' "$1"; }

step "invariants"
scripts/lint-invariants.sh "$BASE" || failed+=(invariants)

step "specs"
node scripts/lint-specs.mjs || failed+=(specs)

step "logic"
if out=$(node --test tests/logic.test.mjs 2>&1); then
  printf '\033[1;32m✓\033[0m %s\n' "$(grep -E '^# pass' <<<"$out" | sed 's/# //') tests"
else
  grep -E '^not ok|^# (pass|fail)' <<<"$out"
  failed+=(logic)
fi

step "manifest"
if command -v omarchy-plugin-validate >/dev/null 2>&1; then
  if omarchy-plugin-validate . >/dev/null 2>&1; then printf '\033[1;32m✓\033[0m omarchy-plugin-validate\n'
  else omarchy-plugin-validate .; failed+=(manifest); fi
else skip "omarchy-plugin-validate not installed; skipped"; fi

step "shader"
QSB=/usr/lib/qt6/bin/qsb
if [[ -x $QSB ]]; then
  tmp=$(mktemp --suffix=.qsb)
  "$QSB" --glsl "100es,120,150" --hlsl 50 --msl 12 -o "$tmp" shaders/aurora.frag
  if [[ $(sha256sum <"$tmp") == $(sha256sum <shaders/aurora.frag.qsb) ]]; then
    printf '\033[1;32m✓\033[0m aurora.frag.qsb rebuilds byte-identical from source\n'
  else
    printf '\033[1;31m✗\033[0m aurora.frag.qsb does not match a rebuild — recompile and update docs/build-provenance.md\n'
    failed+=(shader)
  fi
  rm -f "$tmp"
else skip "qsb not installed; left to CI (shader-provenance.yml)"; fi

echo
if (( ${#failed[@]} )); then
  printf '\033[1;31m✗ check failed:\033[0m %s\n' "${failed[*]}"
  exit 1
fi
printf '\033[1;32m✓ all checks passed\033[0m\n'
