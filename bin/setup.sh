#!/bin/bash
# cc-simple-memory setup script
# Run once after installing the plugin:
#   bash "${CLAUDE_PLUGIN_ROOT}/bin/setup.sh"
#
# What this does:
#   1. Adds Read/Write/Edit permissions for memory files to ~/.claude/settings.json
#   2. Creates ~/bin/claude-memory symlink for terminal access

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS="$HOME/.claude/settings.json"
STATE_FILE="$HOME/.claude/cc-simple-memory-state.json"

# Default symlink target; may be overridden below
SYMLINK="$HOME/bin/claude-memory"

echo "=== cc-simple-memory setup ==="
echo ""

# --- Step 1: Permissions ---
echo "Checking permissions in $SETTINGS..."

REQUIRED_PERMS=(
  "Read(~/.claude/projects/**/memory/*)"
  "Edit(~/.claude/projects/**/memory/*)"
  "Write(~/.claude/projects/**/memory/*)"
  "Read(~/.claude/rules/*)"
  "Edit(~/.claude/rules/*)"
  "Write(~/.claude/rules/*)"
  "Read(~/.claude/memory/*)"
  "Edit(~/.claude/memory/*)"
  "Write(~/.claude/memory/*)"
)

mkdir -p "$(dirname "$SETTINGS")"
if [ ! -f "$SETTINGS" ]; then
  echo '{"permissions":{"allow":[]}}' > "$SETTINGS"
  echo "Created $SETTINGS"
else
  # Backup before mutation
  cp "$SETTINGS" "${SETTINGS}.bak"
  echo "  Backed up to ${SETTINGS}.bak"
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not installed. Install with: brew install jq"
  exit 1
fi

# Validate settings.json is valid JSON before any mutation
if [ -f "$SETTINGS" ]; then
  if ! jq empty "$SETTINGS" 2>/dev/null; then
    echo "ERROR: $SETTINGS is not valid JSON. Fix it manually before running setup."
    echo "  Backup already written to ${SETTINGS}.bak"
    exit 1
  fi
fi

added=0
for perm in "${REQUIRED_PERMS[@]}"; do
  exists=$(jq --arg p "$perm" '.permissions.allow // [] | map(select(. == $p)) | length' "$SETTINGS" 2>/dev/null || echo "0")
  if [ "$exists" = "0" ]; then
    tmp=$(mktemp)
    jq --arg p "$perm" '.permissions.allow = ((.permissions.allow // []) + [$p])' "$SETTINGS" > "$tmp"
    mv "$tmp" "$SETTINGS"
    echo "  Added: $perm"
    added=$((added + 1))
  fi
done

if [ "$added" -eq 0 ]; then
  echo "  All permissions already present. Nothing to add."
else
  echo "  Added $added permission(s). Restart Claude Code for them to take effect."
fi

echo ""

# --- Scrub legacy manual-install hooks from settings.json ---
# If the old ~/.claude/hooks/memory-persistence/ hooks are still registered,
# both old and new plugin hooks will fire simultaneously — causing race conditions
# and duplicate API calls. Remove them now.
echo "Checking for legacy hook entries in settings.json..."
legacy_hooks=$(jq '[
  .hooks.Stop[]?.hooks[]? | select(.command? | test("memory-persistence")),
  .hooks.SessionStart[]?.hooks[]? | select(.command? | test("memory-persistence")),
  .hooks.PreCompact[]?.hooks[]? | select(.command? | test("memory-persistence"))
] | length' "$SETTINGS" 2>/dev/null || echo "0")

if [ "$legacy_hooks" -gt 0 ]; then
  tmp=$(mktemp)
  # Filter ONLY the matching hook entries within each group's .hooks array.
  # Never drop the parent group — other hooks co-located in the same group are preserved.
  jq '
    def scrub_hooks: map(.hooks = (.hooks | map(select(.command? | test("memory-persistence") | not))));
    .hooks.Stop = (.hooks.Stop // [] | scrub_hooks)
    | .hooks.SessionStart = (.hooks.SessionStart // [] | scrub_hooks)
    | .hooks.PreCompact = (.hooks.PreCompact // [] | scrub_hooks)
  ' "$SETTINGS" > "$tmp"
  mv "$tmp" "$SETTINGS"
  echo "  Removed $legacy_hooks legacy hook entry(s) pointing to ~/.claude/hooks/memory-persistence/"
  echo "  The plugin's hooks.json now handles Stop, PreCompact, and SessionStart."
else
  echo "  No legacy hooks found. Nothing to scrub."
fi

echo ""

# --- Step 2: Symlink ---
# Prefer ~/.local/bin if it exists and is in PATH; fall back to ~/bin
if [ -d "$HOME/.local/bin" ] && [[ ":$PATH:" == *":$HOME/.local/bin:"* ]]; then
  SYMLINK="$HOME/.local/bin/claude-memory"
  echo "Using ~/.local/bin (found in PATH)"
fi
echo "Checking ${SYMLINK} symlink..."

# Persist chosen symlink path so teardown.sh can remove the right file
mkdir -p "$(dirname "$STATE_FILE")"
echo "{\"symlink\": \"$SYMLINK\"}" > "$STATE_FILE"

mkdir -p "$(dirname "$SYMLINK")"
PLUGIN_BIN="${PLUGIN_ROOT}/bin/claude-memory"

if [ -L "$SYMLINK" ]; then
  current=$(readlink "$SYMLINK")
  if [ "$current" = "$PLUGIN_BIN" ]; then
    echo "  Symlink already correct: $SYMLINK -> $PLUGIN_BIN"
  else
    echo "  Updating symlink: $SYMLINK -> $PLUGIN_BIN (was: $current)"
    ln -sf "$PLUGIN_BIN" "$SYMLINK"
  fi
elif [ -f "$SYMLINK" ]; then
  echo "  WARNING: $SYMLINK is a regular file, not a symlink. Remove it manually and re-run."
else
  ln -sf "$PLUGIN_BIN" "$SYMLINK"
  echo "  Created: $SYMLINK -> $PLUGIN_BIN"
fi

echo ""

# --- Step 3: PATH check ---
if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
  echo "WARNING: ~/bin is not in your PATH."
  echo "Add this to your ~/.zshrc or ~/.bashrc:"
  echo "  export PATH=\"\$HOME/bin:\$PATH\""
  echo "Then restart your shell for 'claude-memory' to be available."
else
  echo "~/bin is in PATH. 'claude-memory' will be available after restart."
fi

echo ""
echo "=== Setup complete ==="
echo ""
echo "Next: restart Claude Code for hook and permission changes to take effect."
echo "Then verify with: claude-memory stats"
