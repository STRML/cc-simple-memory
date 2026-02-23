#!/bin/bash
# SessionStart Hook
# Runs on fresh session starts (not resume/compact/clear).
# 1. Checks codemap freshness
# 2. Injects continuous learning instructions into additionalContext

set -euo pipefail

# Require jq — exit silently if missing rather than crashing every session
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

input=$(cat)
source=$(echo "$input" | jq -r '.source // ""' 2>/dev/null || echo "")

if [ "$source" = "resume" ] || [ "$source" = "compact" ] || [ "$source" = "clear" ]; then
  exit 0
fi

context_parts=()

# --- Continuous learning instructions ---
context_parts+=("MEMORY SYSTEM ACTIVE: You have persistent memory at ~/.claude/projects/<project>/memory/MEMORY.md loaded into every session. Actively maintain it — this is how you compound knowledge across sessions. Update MEMORY.md: after discovering a non-obvious technical detail, after debugging something that took multiple turns (save the root cause), when the human corrects a wrong assumption, after trying an approach that failed. How: organize by topic not chronologically, replace outdated info with corrections, keep under 200 lines, only genuinely useful discoveries, prefix critical entries with 📌 (GC never prunes pinned items). The notes are for YOU in future sessions.")

# --- Codemap freshness check ---
codemaps_dir="$(pwd)/codemaps"

if [ -d "$codemaps_dir" ]; then
  stale_count=$(find "$codemaps_dir" -name "*.md" -mtime +7 2>/dev/null | wc -l | tr -d ' ' || echo "0")
  total_count=$(find "$codemaps_dir" -name "*.md" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
  if [ "$stale_count" -gt 0 ] && [ "$total_count" -gt 0 ]; then
    context_parts+=("Codemaps are stale (${stale_count}/${total_count} files older than 7 days). Run /update-codemaps to refresh.")
  fi
elif git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  src_count=$(find "$(pwd)" -maxdepth 3 \( -name "*.rs" -o -name "*.ts" -o -name "*.js" -o -name "*.py" -o -name "*.swift" -o -name "*.go" \) -not -path "*/node_modules/*" -not -path "*/target/*" -not -path "*/.build/*" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
  if [ "$src_count" -gt 5 ]; then
    context_parts+=("No codemaps/ found (${src_count} source files). Consider running /update-codemaps.")
  fi
fi

# Output JSON with additionalContext
if [ ${#context_parts[@]} -gt 0 ]; then
  message=$(printf '%s ' "${context_parts[@]}")
  jq -n --arg ctx "$message" '{
    "hookSpecificOutput": {
      "hookEventName": "SessionStart",
      "additionalContext": $ctx
    }
  }'
fi
