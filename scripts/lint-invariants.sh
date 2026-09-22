#!/usr/bin/env bash
#
# lint-invariants.sh — the rules this project learned the hard way, enforced.
#
# Each rule here exists because breaking it once cost real time, and each is
# stated in AGENTS.md with its reason. Prose is not enough: an agent (or a
# person) that has not read the story will break the rule again, so the rule
# lives here as a check that fails the build instead.
#
# Usage: scripts/lint-invariants.sh [base-ref]
#   base-ref  what the shader's uniform block must still be a prefix of
#             (default: HEAD; CI passes the target branch)

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

QML=BorealisAtlas.qml
FRAG=shaders/aurora.frag
BASE=${1:-HEAD}
fail=0

bad() { printf '\033[1;31m✗\033[0m %s\n' "$1"; shift; for l in "$@"; do printf '    %s\n' "$l"; done; fail=1; }
ok()  { printf '\033[1;32m✓\033[0m %s\n' "$1"; }

# ---- 1. every Text renders plain text --------------------------------------
# Text defaults to AutoText, which interprets anything that looks like markup.
# Place names come from a geocoder and conditions from a forecast service, so a
# reply containing <b> or an <img> tag would be rendered, not shown.
missing=$(awk '
  FNR == 1 { file = FILENAME }
  /^[[:space:]]*Text[[:space:]]*\{/ { in_text = 1; depth = 0; start = FNR; plain = 0 }
  in_text {
    line = $0
    n_open = gsub(/\{/, "{", line); n_close = gsub(/\}/, "}", line)
    depth += n_open - n_close
    if ($0 ~ /textFormat:[[:space:]]*Text\.PlainText/) plain = 1
    if (depth <= 0) { if (!plain) print file ":" start; in_text = 0 }
  }' ./*.qml)
if [[ -z $missing ]]; then ok "every Text has textFormat: Text.PlainText"
else bad "Text without textFormat: Text.PlainText" $missing; fi

# ---- 2. JSON is parsed in exactly one place --------------------------------
# boundedParse caps the size and refuses non-objects. A second JSON.parse
# anywhere is a reply that skipped both checks.
# The function's real extent, found by matching its braces: a fixed line window
# was tried first and let a JSON.parse in the very next function straight
# through, which is exactly how a mutation test caught it.
read -r bp_start bp_end < <(awk '
  /function boundedParse\(/ { s = FNR; on = 1; d = 0 }
  on { t = $0; d += gsub(/\{/, "", t); t = $0; d -= gsub(/\}/, "", t)
       if (d == 0 && FNR > s) { print s, FNR; exit } }' "$QML")
stray=""
for h in $(grep -n 'JSON\.parse(' "$QML" | cut -d: -f1); do
  (( h > bp_start && h < bp_end )) || stray+="$QML:$h "
done
if [[ -z $stray ]]; then ok "JSON.parse only inside boundedParse"
else bad "JSON.parse outside boundedParse (route it through boundedParse)" $stray; fi

# ---- 3. curl never retries on its own --------------------------------------
# curl counts HTTP 429 as transient, so --retry answers a rate limit with more
# requests against the limiter that just refused. Retrying belongs to topUp(),
# which knows what a 429 means and backs off.
if grep -nE '"--retry' "$QML" >/dev/null; then
  bad "curl is given --retry" $(grep -nE '"--retry' "$QML" | cut -d: -f1 | sed "s|^|$QML:|")
else ok "curl is never given --retry"; fi

# ---- 4. no const arrays in the shader --------------------------------------
# qsb compiles them happily, but the GLSL 120 target the shell may run cannot
# express them: the overlay goes blank at runtime with C7516.
if grep -nE '^\s*const\s+\w+\s+\w+\s*\[' "$FRAG" >/dev/null; then
  bad "const array in the shader (use uniforms or unrolled code)" \
      $(grep -nE '^\s*const\s+\w+\s+\w+\s*\[' "$FRAG" | cut -d: -f1 | sed "s|^|$FRAG:|")
else ok "no const arrays in the shader"; fi

# ---- 5. the uniform block only ever grows at the end -----------------------
# A member inserted anywhere but last shifts the std140 offsets of everything
# after it, and those members are then silently never written: no error, just
# a scene that ignores its data.
block() { awk '/uniform buf \{/{on=1; next} on && /^\};/{exit} on' | grep -oE '^\s*(mat4|vec[234]|float|int)\s+\w+' | awk '{print $2}'; }
if git rev-parse -q --verify "$BASE:$FRAG" >/dev/null 2>&1; then
  was=$(git show "$BASE:$FRAG" | block)
  now=$(block < "$FRAG")
  if [[ "$(printf '%s\n' "$now" | head -n "$(printf '%s\n' "$was" | wc -l)")" == "$was" ]]; then
    ok "uniform block only appends (vs $BASE)"
  else
    bad "uniform block changed other than by appending (vs $BASE)" \
        "was: $(echo $was)" "now: $(echo $now)"
  fi
else ok "uniform block: no $FRAG at $BASE to compare against"; fi

# ---- 6. no elevation request exceeds 100 points ----------------------------
# The elevation API accepts exactly 100 coordinates and answers 101 with a 400.
n() { grep -oE "property (int|real) $1:\s*[0-9.]+" "$QML" | grep -oE '[0-9.]+$' | cut -d. -f1; }
list_len() { grep -oE "property var $1:\s*\[[^]]*\]" "$QML" | tr -cd ',' | wc -c | awk '{print $1+1}'; }
near=$(( $(n nearN) * $(n nearN) ))
ring=$(( 1 + $(n hzAz) * $(list_len hzRings) ))
fan=$(( $(n hzFanAz) * $(list_len hzFan) ))
if (( near <= 100 && ring <= 100 && fan <= 100 )); then
  ok "elevation requests ≤ 100 points (near $near, ring $ring, fan $fan)"
else bad "an elevation request exceeds 100 points" "near $near, ring $ring, fan $fan"; fi

# ---- 7. every network Process reports how it failed ------------------------
# Without stderr and onExited, a dead network and a malformed reply arrive as
# the same empty string, and the status line cannot tell the user which.
unreported=$(awk '
  /^  Process \{/ { in_p = 1; body = ""; id = "" }
  in_p { body = body $0 "\n"; if ($0 ~ /id: /) { id = $0; sub(/.*id: /, "", id) } }
  in_p && /^  \}/ {
    if (body ~ /property string src:/ && (body !~ /stderr:/ || body !~ /onExited:/)) print id
    in_p = 0
  }' "$QML")
unsourced=""
for p in $(grep -oE '[a-zA-Z]+Proc\.command = root\.curlCmd' "$QML" | cut -d. -f1 | sort -u); do
  awk -v id="$p" '/^  Process \{/{b=""} {b=b $0 "\n"} /^  \}/ && b ~ ("id: " id "\n") && b ~ /property string src:/ {f=1} END{exit !f}' "$QML" \
    || unsourced+="$p "
done
if [[ -z $unreported && -z $unsourced ]]; then ok "network Processes declare src, stderr and onExited"
else bad "network Process without failure reporting" ${unreported:+"missing stderr/onExited: $unreported"} ${unsourced:+"no src: $unsourced"}; fi

# ---- 8. the provenance doc states the digests that actually ship -----------
for f in shaders/aurora.frag shaders/aurora.frag.qsb; do
  d=$(sha256sum "$f" | cut -d' ' -f1)
  if grep -q "$d" docs/build-provenance.md; then ok "build-provenance.md records $f"
  else bad "docs/build-provenance.md does not record the digest of $f" "$d"; fi
done

# ---- 9. one plugin id everywhere --------------------------------------------
# The id is also the install directory name; the QML fallback must agree with
# the manifest or a copy installed without the manifest id breaks its own cache.
mid=$(grep -oE '"id":\s*"[^"]+"' manifest.json | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
if grep -q "|| \"$mid\"" "$QML"; then ok "QML fallback id matches manifest ($mid)"
else bad "QML fallback pluginId does not match manifest id $mid"; fi

exit $fail
