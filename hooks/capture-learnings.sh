#!/bin/bash
# Capture session learnings on /clear
# Spawns a background Claude to analyze the transcript and update CLAUDE.md
#
# Opt-out: Set CLAUDE_SKIP_SESSION_LEARNINGS=1 to disable

set -euo pipefail

# Opt-out check
if [ "${CLAUDE_SKIP_SESSION_LEARNINGS:-}" = "1" ]; then
  exit 0
fi

# Guard: claude CLI must be available
command -v claude >/dev/null 2>&1 || exit 0

input=$(cat)
reason=$(echo "$input" | jq -r '.reason // ""')
transcript_path=$(echo "$input" | jq -r '.transcript_path // ""')
cwd=$(echo "$input" | jq -r '.cwd // ""')

# Only run on clear (not logout, prompt_input_exit, etc.)
if [ "$reason" != "clear" ]; then
  exit 0
fi

# Verify transcript exists
if [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ]; then
  exit 0
fi

mkdir -p /tmp/claude

# Spawn claude in background with minimal context:
# - CLAUDE_SKIP_SESSION_LEARNINGS=1 to prevent recursion
# - --no-session-persistence for simple stateless query
# - --model sonnet --effort low for fast/cheap but high-quality extraction
# - --tools Read,Write,Edit (only what's needed)
# - --disable-slash-commands (no skills)
# - --strict-mcp-config (no MCP servers)
cd "$cwd"
CLAUDE_SKIP_SESSION_LEARNINGS=1 CLAUDECODE="" CLAUDE_CODE_ENTRYPOINT="" \
  claude --print --model sonnet --effort low --no-session-persistence \
  --tools "Read,Write,Edit" \
  --disable-slash-commands \
  --strict-mcp-config \
  --system-prompt "You extract session learnings and update CLAUDE.md files. Be concise." \
  "Read the session transcript at $transcript_path. Extract any important discoveries, gotchas, patterns, or lessons learned. If there are meaningful learnings worth preserving, update the project's CLAUDE.md file (create .claude/CLAUDE.md if it doesn't exist) with a concise summary. Focus on project-specific insights that would help future sessions. If no significant learnings, do nothing silently." \
  >>/tmp/claude/capture-learnings.log 2>&1 &
disown

exit 0
