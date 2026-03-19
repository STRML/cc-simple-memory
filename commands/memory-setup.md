---
description: Check cc-simple-memory setup status and guide post-install configuration
---

# /memory-setup

Check the current setup status of the cc-simple-memory plugin and guide the user through any remaining post-install steps.

## Current Status

!`bash -c 'settings="$HOME/.claude/settings.json"; perms=""; if [ -f "$settings" ]; then perms=$(cat "$settings"); fi; echo "### Permissions"; for p in "Read(~/.claude/projects/**/memory/*)" "Edit(~/.claude/projects/**/memory/*)" "Write(~/.claude/projects/**/memory/*)" "Read(~/.claude/rules/*)" "Edit(~/.claude/rules/*)" "Write(~/.claude/rules/*)" "Read(~/.claude/memory/*)" "Edit(~/.claude/memory/*)" "Write(~/.claude/memory/*)"; do if echo "$perms" | grep -qF "$p"; then echo "- ✅ $p"; else echo "- ❌ $p"; fi; done; echo ""; echo "### CLI Symlink"; found=0; for loc in "$HOME/bin/claude-memory" "$HOME/.local/bin/claude-memory"; do if [ -L "$loc" ]; then echo "- ✅ $loc -> $(readlink "$loc")"; found=1; elif [ -x "$loc" ]; then echo "- ✅ $loc (exists, not a symlink)"; found=1; fi; done; [ "$found" -eq 0 ] && echo "- ❌ No symlink found at ~/bin/ or ~/.local/bin/"; if [ -f "$HOME/.claude/cc-simple-memory-state.json" ]; then echo ""; echo "### State"; cat "$HOME/.claude/cc-simple-memory-state.json"; fi'`

## Instructions

Review the status above and report it to the user.

- If everything shows ✅, tell the user the plugin is fully configured.
- If anything shows ❌, tell the user to run setup in their terminal:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/bin/setup.sh"
   ```

   The plugin is installed at: !`echo "${CLAUDE_PLUGIN_ROOT}"`

- After they confirm they've run it, invoke `/memory-setup` again to verify.
