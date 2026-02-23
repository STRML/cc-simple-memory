#!/bin/bash
# Stop hook — extract learnings from session transcript into MEMORY.md
# Delegates all logic to the claude-memory CLI.
# Opt-out: CLAUDE_SKIP_SESSION_LEARNINGS=1

[ "${CLAUDE_SKIP_SESSION_LEARNINGS:-}" = "1" ] && exit 0

# Guard: CLAUDE_PLUGIN_ROOT must be set and the binary must exist
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || exit 0
[ -x "${CLAUDE_PLUGIN_ROOT}/bin/claude-memory" ] || exit 0

project_cwd="${CLAUDE_PROJECT_DIR:-$(pwd)}"
[ -z "$project_cwd" ] && exit 0

# Always exit 0 — Stop hooks must never fail.
# Pass CLAUDE_PROJECT_DIR explicitly so the CLI extracts for the correct project.
CLAUDE_PROJECT_DIR="$project_cwd" "${CLAUDE_PLUGIN_ROOT}/bin/claude-memory" extract || true
