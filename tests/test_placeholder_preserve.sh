#!/usr/bin/env bash
# Regression: a no-content session must not clobber existing MEMORY.md or global
# memory. The extraction agent (stubbed here) returns a "(no session content)"
# placeholder; the fix keeps the existing files instead of overwriting them.
#
# SAFETY: this test runs the real claude-memory script with a fake HOME. A bug in
# the setup could point it at the real $HOME and overwrite real memory, so we
# hard-fail unless HOME is provably a throwaway dir created by this test.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$HERE")"
REAL_HOME="${HOME:?}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ccsm-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# Guard 1: HOME must be a fresh dir we just made, inside our temp root, and must
# differ from the caller's real HOME. Any violation aborts before any write.
HOME="$TMP/home"
case "$HOME" in
  "$TMP"/home) ;;                       # exactly where we put it
  *) echo "REFUSING: HOME=$HOME is not our throwaway dir" >&2; exit 3 ;;
esac
if [ "$HOME" = "$REAL_HOME" ]; then
  echo "REFUSING: HOME would equal the real home" >&2; exit 3
fi
mkdir -p "$HOME"

# Guard 2: sanity — the real home must not be inside our temp root either.
case "$REAL_HOME" in
  "$TMP"/*) echo "REFUSING: real home is inside temp root" >&2; exit 3 ;;
esac

# Fake project dir. claude-memory derives the project path from CLAUDE_PROJECT_DIR.
PROJ_DIR="$TMP/work/proj"
export CLAUDE_PROJECT_DIR="$PROJ_DIR"
ENCODED="$(printf '%s' "$PROJ_DIR" | sed 's|[/.]|-|g')"
CLAUDE_PROJ="$HOME/.claude/projects/$ENCODED"
mkdir -p "$CLAUDE_PROJ/memory" "$HOME/.claude/rules"

# Existing memory that must survive the placeholder extraction.
printf '%s\n' "- [existing note](existing.md) — important thing" \
  > "$CLAUDE_PROJ/memory/MEMORY.md"
printf '%s\n' "- [global note](global.md) — universal thing" \
  > "$HOME/.claude/rules/global-memory.md"

# Transcript must live in the encoded project dir (that is where the script looks)
# and have >= 5 user messages or the script skips before the write-back. 6 here.
printf '%s\n' \
  '{"type":"user","message":{"role":"user","content":"hi"}}' \
  '{"type":"assistant","message":{"role":"assistant","content":"hello"}}' \
  '{"type":"user","message":{"role":"user","content":"how are you"}}' \
  '{"type":"assistant","message":{"role":"assistant","content":"fine"}}' \
  '{"type":"user","message":{"role":"user","content":"second"}}' \
  '{"type":"assistant","message":{"role":"assistant","content":"ok"}}' \
  '{"type":"user","message":{"role":"user","content":"third"}}' \
  '{"type":"assistant","message":{"role":"assistant","content":"yes"}}' \
  '{"type":"user","message":{"role":"user","content":"fourth"}}' \
  '{"type":"assistant","message":{"role":"assistant","content":"done"}}' \
  > "$CLAUDE_PROJ/session.jsonl"

# Stub `claude -p` to return a no-content placeholder (what the extraction agent
# emits when a session has nothing meaningful).
STUB="$TMP/bin/claude"
mkdir -p "$TMP/bin"
printf '#!/usr/bin/env bash\ncat "%s"\n' "$TMP/placeholder.txt" > "$STUB"
chmod +x "$STUB"
printf '%s\n' \
  '## Feedback' \
  '(none — no session content to extract)' \
  '---GLOBAL_MEMORY_SEPARATOR---' \
  '(no global memory updates — no session content provided)' \
  '---DECISIONS_SEPARATOR---' \
  '(none)' \
  > "$TMP/placeholder.txt"
export PATH="$TMP/bin:$PATH"

# Run extract (real script, stubbed agent). It launches a background job, so
# wait for the memory file to be touched (or for the job to finish) before
# asserting, and never let the trap's rm race the background write.
"$REPO/bin/claude-memory" extract >/dev/null 2>&1 || true

MEM="$CLAUDE_PROJ/memory/MEMORY.md"
GLOB="$HOME/.claude/rules/global-memory.md"

for _ in $(seq 1 50); do
  # The fix keeps the file unchanged on a placeholder, so "existing note" is the
  # signal that the background job has at least started/finished touching it.
  grep -q "existing note" "$MEM" 2>/dev/null && grep -q "global note" "$GLOB" 2>/dev/null && break
  sleep 0.2
done
sleep 1   # give the background job a moment to fully finish before the trap runs

# Guard 3: the writes must have landed under our fake HOME, never the real one.
# Canonicalize both sides with pwd -P because readlink -f is not portable and
# /tmp can resolve to /private/tmp.
canon_home="$(cd "$HOME" && pwd -P)"
mem_canon="$(cd "$(dirname "$MEM")" && pwd -P)/$(basename "$MEM")"
glob_canon="$(cd "$(dirname "$GLOB")" && pwd -P)/$(basename "$GLOB")"
case "$mem_canon" in
  "$canon_home"/*) ;;
  *) echo "REFUSING: MEMORY.md not under fake HOME: $mem_canon" >&2; exit 3 ;;
esac
case "$glob_canon" in
  "$canon_home"/*) ;;
  *) echo "REFUSING: global-memory.md not under fake HOME: $glob_canon" >&2; exit 3 ;;
esac

fail=0
grep -q "existing note" "$MEM" || { echo "FAIL: project MEMORY.md clobbered"; fail=1; }
grep -q "global note" "$GLOB" || { echo "FAIL: global memory clobbered"; fail=1; }
grep -qi "no session content" "$MEM" && { echo "FAIL: placeholder leaked into MEMORY.md"; fail=1; }
grep -qi "no global memory updates" "$GLOB" && { echo "FAIL: placeholder leaked into global memory"; fail=1; }

if [ "$fail" -eq 0 ]; then
  echo "PASS: existing memory preserved on placeholder extraction"
else
  echo "--- MEMORY.md now: ---"; cat "$MEM"
  echo "--- global now: ---"; cat "$GLOB"
  exit 1
fi
