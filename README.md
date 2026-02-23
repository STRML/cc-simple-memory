# cc-simple-memory

Persistent cross-session memory for Claude Code. Hooks extract learnings automatically into per-project and global `MEMORY.md` files that Claude reads at the start of every session.

## How it works

```
Session → Claude writes MEMORY.md proactively (instructed via SessionStart hook)
Stop    → extract-learnings.sh → claude-memory extract → background Sonnet writes MEMORY.md
/clear  → capture-learnings.sh → background Sonnet writes project CLAUDE.md
Every 10th extraction → gc-memory.sh → Opus consolidates + archives stale entries
```

## Installation

### 1. Install the plugin

```bash
/plugin marketplace add /path/to/cc-simple-memory
/plugin install cc-simple-memory@cc-simple-memory-dev
```

Restart Claude Code.

### 2. Run setup

In your terminal (not inside Claude):

```bash
PLUGIN_DIR=$(ls -dt ~/.claude/plugins/cache/*/cc-simple-memory 2>/dev/null | head -1)
[ -z "$PLUGIN_DIR" ] && echo "Plugin not found in cache" && exit 1
bash "${PLUGIN_DIR}/bin/setup.sh"
```

Or run `/memory-setup` inside Claude to check status and get the exact command.

Setup adds nine permission entries to `~/.claude/settings.json`, creates a `~/bin/claude-memory` (or `~/.local/bin/`) symlink, and scrubs any legacy hook entries from the old manual install.

### 3. Restart Claude Code again

Permission changes require a restart to take effect.

## Usage

Memory updates happen automatically. Use `claude-memory` in your terminal to inspect:

```bash
claude-memory show                  # Display project + global memory
claude-memory stats                 # Sizes, transcript counts, log activity
claude-memory log                   # Recent extraction log
claude-memory search "query"        # Search project transcripts
claude-memory extract --dry-run     # Preview what extraction would find
claude-memory gc --dry-run          # Preview GC without writing
claude-memory show archive          # View cold storage
```

Or use the `/memory-setup` slash command to check configuration status.

## Memory locations

| File | Purpose | Auto-loaded |
|------|---------|-------------|
| `~/.claude/projects/<encoded>/memory/MEMORY.md` | Per-project memory | ✅ |
| `~/.claude/projects/<encoded>/memory/ARCHIVE.md` | Per-project cold storage | ❌ |
| `~/.claude/rules/global-memory.md` | Cross-project memory | ✅ everywhere |
| `~/.claude/memory/global-archive.md` | Global cold storage | ❌ |

Path encoding: Claude Code replaces both `/` and `.` with `-`.

## Opt-out

Add `SKIP_MEMORY_EXTRACTION` on its own line in a session to skip Stop hook extraction for that session.

Set `CLAUDE_SKIP_SESSION_LEARNINGS=1` before starting a session to skip all extraction.

## Cost

| Operation | Model | Frequency | Cost |
|-----------|-------|-----------|------|
| Extraction (Stop hook) | Sonnet medium | Max 1/hr/project | ~$0.10 |
| Condensation pre-pass | Haiku low | Long sessions only | ~$0.01 |
| /clear capture | Sonnet low | On /clear | ~$0.05 |
| GC pass | Opus low | Every 10 extractions | ~$0.15 |
