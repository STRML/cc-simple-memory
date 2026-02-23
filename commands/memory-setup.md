---
description: Check cc-simple-memory setup status and guide post-install configuration
---

# /memory-setup

Check the current setup status of the cc-simple-memory plugin and guide the user through any remaining post-install steps.

## Steps

1. Read `~/.claude/settings.json` and check whether the following permissions are present in `permissions.allow`:
   - `Read(~/.claude/projects/**/memory/*)`
   - `Edit(~/.claude/projects/**/memory/*)`
   - `Write(~/.claude/projects/**/memory/*)`
   - `Read(~/.claude/rules/*)`
   - `Edit(~/.claude/rules/*)`
   - `Write(~/.claude/rules/*)`
   - `Read(~/.claude/memory/*)`
   - `Edit(~/.claude/memory/*)`
   - `Write(~/.claude/memory/*)`

2. Check whether `~/bin/claude-memory` OR `~/.local/bin/claude-memory` exists and is a symlink. Also read `~/.claude/cc-simple-memory-state.json` if it exists to see which location was chosen by setup.sh.

3. Report status clearly:
   - ✅ for items already configured
   - ❌ for items missing

4. If anything is missing, tell the user to run the setup script in their terminal:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/bin/setup.sh"
   ```

   Substitute the actual `${CLAUDE_PLUGIN_ROOT}` path (find it by checking where the plugin is installed: `ls ~/.claude/plugins/cache/`).

5. After they confirm they've run it, verify the permissions are now present in settings.json and report the final status.
