#!/usr/bin/env bash
# Unit test for is_placeholder, pinned against the exact texts that were found
# sitting in real MEMORY.md files after a clobber. The integration test
# (test_placeholder_preserve.sh) covers one placeholder shape end to end; this
# one covers the shapes cheaply and says which shape regressed.
#
# The function is extracted from bin/claude-memory rather than copied, so a
# change to the regex is tested and a copy can never drift out of sync.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$HERE")"
SRC="$REPO/bin/claude-memory"

[ -r "$SRC" ] || { echo "FAIL: cannot read $SRC" >&2; exit 3; }

fn="$(sed -n '/^ *is_placeholder() {$/,/^ *}$/p' "$SRC")"
[ -n "$fn" ] || { echo "FAIL: is_placeholder not found in $SRC (did it get renamed?)" >&2; exit 3; }
eval "$fn"

fail=0

expect_placeholder() {
  if is_placeholder "$2"; then
    echo "  ok   caught: $1"
  else
    echo "  FAIL missed: $1"; fail=1
  fi
}

expect_real() {
  if is_placeholder "$2"; then
    echo "  FAIL real memory misread as placeholder: $1"; fail=1
  else
    echo "  ok   kept: $1"
  fi
}

echo "# placeholder shapes that reached disk"

# react-grid-layout/memory/MEMORY.md, 2026-08-07. A reply to the human, not a
# document — no "no ... content" phrase anywhere in it.
expect_placeholder "conversational reply asking for a transcript" \
"I don't see any session content to extract from. My job is to update the project's MEMORY.md, global memory, and decision log based on a completed session — but you've only sent \"X\" with no conversation transcript, code changes, or debugging insights to analyze.

Please paste the session transcript, the conversation you'd like me to extract learnings from, or the diff/context that contains the discoveries."

# cc-debate/memory/MEMORY.md, 2026-08-07. Has the phrase, but wrapped in
# markdown italics so a whitespace-anchored boundary never matched.
expect_placeholder "placeholder wrapped in markdown italics" \
"# MEMORY.md

_(No session content to extract — no discoveries, corrections, or decisions were made in this session.)_"

# krisper, 2026-08-02. Caught before this fix; must stay caught.
expect_placeholder "bare no-content sentence" \
"No session content was provided to extract from. No learnings, corrections, or decisions are available to record."

# volatrick, 2026-03-13. Caught before this fix; must stay caught.
expect_placeholder "parenthesised stub" \
"(empty project memory — no session content to extract)"

echo "# real memory that must survive"

expect_real "an index of topic files" \
"# MEMORY.md

- [RGL v2 key facts](rgl-v2-key-facts.md) — verified codebase facts that anchor bug triage.
- [RGL triage setup](rgl-triage-setup.md) — label mapping and workflow for triaging issues."

expect_real "sectioned memory with real bullets" \
"## Key Facts
- The proxy clamps max_out on the direct profile only.
- CI on fork PRs sits at action_required until a maintainer approves each run."

if [ "$fail" -eq 0 ]; then
  echo "PASS: every known placeholder shape is caught and real memory survives"
else
  exit 1
fi
