#!/bin/bash
# cc-simple-memory teardown script
# Run before uninstalling the plugin:
#   bash "${CLAUDE_PLUGIN_ROOT}/bin/teardown.sh"
#
# What this does:
#   1. Removes the ~/bin/claude-memory symlink
#   2. Removes cc-simple-memory permissions from ~/.claude/settings.json

set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
STATE_FILE="$HOME/.claude/cc-simple-memory-state.json"

# Read symlink path written by setup.sh; fall back to ~/bin default
if [ -f "$STATE_FILE" ] && command -v jq >/dev/null 2>&1; then
  SYMLINK=$(jq -r '.symlink // ""' "$STATE_FILE" 2>/dev/null || echo "")
fi
SYMLINK="${SYMLINK:-$HOME/bin/claude-memory}"

echo "=== cc-simple-memory teardown ==="
echo ""

# --- Step 1: Remove symlink ---
if [ -L "$SYMLINK" ]; then
  rm "$SYMLINK"
  echo "Removed symlink: $SYMLINK"
else
  echo "No symlink found at $SYMLINK — skipping"
fi

echo ""

# --- Step 2: Remove permissions ---
if [ ! -f "$SETTINGS" ]; then
  echo "No settings.json found — nothing to clean up"
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq required but not installed. Remove these entries from $SETTINGS manually:"
  echo "  Read(~/.claude/projects/**/memory/*)"
  echo "  Edit(~/.claude/projects/**/memory/*)"
  echo "  Write(~/.claude/projects/**/memory/*)"
  echo "  Read(~/.claude/rules/*)"
  echo "  Edit(~/.claude/rules/*)"
  echo "  Write(~/.claude/rules/*)"
  exit 1
fi

cp "$SETTINGS" "${SETTINGS}.bak"

tmp=$(mktemp)
jq '.permissions.allow = (.permissions.allow // [] | map(select(
  . != "Read(~/.claude/projects/**/memory/*)" and
  . != "Edit(~/.claude/projects/**/memory/*)" and
  . != "Write(~/.claude/projects/**/memory/*)" and
  . != "Read(~/.claude/rules/*)" and
  . != "Edit(~/.claude/rules/*)" and
  . != "Write(~/.claude/rules/*)" and
  . != "Read(~/.claude/memory/*)" and
  . != "Edit(~/.claude/memory/*)" and
  . != "Write(~/.claude/memory/*)"
)))' "$SETTINGS" > "$tmp"
mv "$tmp" "$SETTINGS"
echo "Removed permissions from $SETTINGS (backup at ${SETTINGS}.bak)"

echo ""
echo "=== Teardown complete ==="
echo "You can now run: /plugin uninstall cc-simple-memory"
