#!/usr/bin/env bash
# Regression: when a session HAS meaningful content, extraction must still merge
# it into MEMORY.md (the placeholder-preservation guard must not suppress real
# writes). Same hardened fake-HOME scaffolding as test_placeholder_preserve.sh.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$HERE")"
REAL_HOME="${HOME:?}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ccsm-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

HOME="$TMP/home"
case "$HOME" in "$TMP"/home) ;; *) echo "REFUSING: bad HOME" >&2; exit 3 ;; esac
[ "$HOME" != "$REAL_HOME" ] || { echo "REFUSING: HOME==real home" >&2; exit 3; }
case "$REAL_HOME" in "$TMP"/*) echo "REFUSING: real home inside temp" >&2; exit 3 ;; esac
mkdir -p "$HOME"

PROJ_DIR="$TMP/work/proj"
export CLAUDE_PROJECT_DIR="$PROJ_DIR"
ENCODED="$(printf '%s' "$PROJ_DIR" | sed 's|[/.]|-|g')"
CLAUDE_PROJ="$HOME/.claude/projects/$ENCODED"
mkdir -p "$CLAUDE_PROJ/memory" "$HOME/.claude/rules"

# Existing memory plus the transcript (6 user messages so the write path runs).
printf '%s\n' "- [old note](old.md) — pre-existing" > "$CLAUDE_PROJ/memory/MEMORY.md"
printf '%s\n' '{"type":"user","message":{"role":"user","content":"hi"}}' \
  '{"type":"assistant","message":{"role":"assistant","content":"hello"}}' \
  '{"type":"user","message":{"role":"user","content":"a"}}' \
  '{"type":"assistant","message":{"role":"assistant","content":"b"}}' \
  '{"type":"user","message":{"role":"user","content":"c"}}' \
  '{"type":"assistant","message":{"role":"assistant","content":"d"}}' \
  '{"type":"user","message":{"role":"user","content":"e"}}' \
  '{"type":"assistant","message":{"role":"assistant","content":"f"}}' \
  '{"type":"user","message":{"role":"user","content":"g"}}' \
  '{"type":"assistant","message":{"role":"assistant","content":"h"}}' \
  > "$CLAUDE_PROJ/session.jsonl"

# Stub claude to return real merged content (old preserved + new added).
STUB="$TMP/bin/claude"; mkdir -p "$TMP/bin"
printf '#!/usr/bin/env bash\ncat "%s"\n' "$TMP/real.txt" > "$STUB"
chmod +x "$STUB"
printf '%s\n' \
  '- [old note](old.md) — pre-existing' \
  '- [new note](new.md) — brand new discovery' \
  '---GLOBAL_MEMORY_SEPARATOR---' \
  '(no global memory updates — no session content provided)' \
  '---DECISIONS_SEPARATOR---' \
  '(none)' \
  > "$TMP/real.txt"
export PATH="$TMP/bin:$PATH"

"$REPO/bin/claude-memory" extract >/dev/null 2>&1 || true

MEM="$CLAUDE_PROJ/memory/MEMORY.md"
canon_home="$(cd "$HOME" && pwd -P)"
mem_canon="$(cd "$(dirname "$MEM")" && pwd -P)/$(basename "$MEM")"
case "$mem_canon" in "$canon_home"/*) ;; *) echo "REFUSING: MEMORY.md outside fake HOME" >&2; exit 3 ;; esac

# Extract runs a background job; wait for the new content to land before
# asserting, and keep the temp dir alive until the write completes.
for _ in $(seq 1 50); do
  grep -q "brand new" "$MEM" 2>/dev/null && break
  sleep 0.2
done
sleep 1   # give the background job a moment to fully finish before the trap runs

fail=0
grep -q "brand new" "$MEM" || { echo "FAIL: new content not written"; fail=1; }
grep -q "old note" "$MEM" || { echo "FAIL: old content lost"; fail=1; }
if [ "$fail" -eq 0 ]; then
  echo "PASS: real content merged into MEMORY.md"
else
  echo "--- MEMORY.md now: ---"; cat "$MEM"
  exit 1
fi
