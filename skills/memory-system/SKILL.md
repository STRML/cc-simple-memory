---
name: memory-system
description: Reference for the Claude Code persistent memory system. Use when running claude-memory commands, managing MEMORY.md files, debugging extraction/GC, or understanding how cross-session memory works.
version: "1.0.0"
---

# Memory System Reference

## Architecture

Two-layer memory. Proactive in-session updates (via CLAUDE.md) are primary. Stop hook runs background Sonnet extraction as a safety net. Opus GC prevents unbounded growth.

```
Session → Claude writes MEMORY.md proactively
Stop    → extract-learnings.sh (Sonnet, background, detached)
Every 10th extraction → gc-memory.sh (Opus, consolidates + archives)
/clear  → capture-learnings.sh (Sonnet, before context discarded)
```

## File Paths

| File | Purpose |
|------|---------|
| `~/.claude/projects/<encoded-path>/memory/MEMORY.md` | Project memory (auto-loaded) |
| `~/.claude/projects/<encoded-path>/memory/ARCHIVE.md` | Cold storage (GC only) |
| `~/.claude/rules/global-memory.md` | Global cross-project memory (auto-loaded everywhere) |
| `~/.claude/memory/global-archive.md` | Global cold storage |
| `${CLAUDE_PLUGIN_ROOT}/hooks/extract-learnings.sh` | Stop hook (background Sonnet) |
| `${CLAUDE_PLUGIN_ROOT}/hooks/gc-memory.sh` | GC hook (Opus, every 10 extractions) |
| `${CLAUDE_PLUGIN_ROOT}/hooks/capture-learnings.sh` | /clear hook (Sonnet) |
| `${CLAUDE_PLUGIN_ROOT}/bin/claude-memory` | CLI tool |

### Path Encoding
📌 Both `/` AND `.` are replaced with `-`: `sed 's|[/.]|-|g'`

## claude-memory CLI

Located at `${CLAUDE_PLUGIN_ROOT}/bin/claude-memory` (symlinked to `~/bin/claude-memory` by setup.sh).

```bash
claude-memory show                  # Display project + global memory
claude-memory search "query"        # Search current project transcripts
claude-memory search "query" --all  # Search ALL project transcripts
claude-memory log                   # Recent extraction activity
claude-memory stats                 # Memory sizes, transcript counts
claude-memory extract --dry-run     # Preview extraction without writing
claude-memory gc                    # Run Opus GC on oversized memory files
claude-memory gc --dry-run          # Preview GC output without writing
claude-memory show archive          # View archived (cold storage) items
```

## Nested claude -p Invocation Pattern

Stop/GC hooks run nested `claude -p`. Critical env vars:

```bash
CLAUDECODE="" CLAUDE_CODE_ENTRYPOINT="" CLAUDE_CODE_SIMPLE=1 \
  claude -p --model haiku --effort low \
  --no-session-persistence --tools "" --disable-slash-commands \
  --strict-mcp-config --settings '{"disableAllHooks":true}' ...
```

- `CLAUDE_CODE_SIMPLE=1` cuts token cost from ~6-8k → ~200 (skips CLAUDE.md/skills/MCP)
- GC uses `--model sonnet --effort medium`
- **Never redirect stdin to `/dev/null`** — kills the process silently
- Sandbox blocks `claude` CLI network — test nested CLI from real terminal

## Hook Gotchas

- `disown` required after `&` — Claude Code waits on process group otherwise
- Stop hooks must not print to stdout (Claude Code expects JSON) and must always exit 0
- `CLAUDECODE="" CLAUDE_CODE_ENTRYPOINT=""` required — nested `claude -p` fails silently otherwise
- GC must run sequentially after extraction (race conditions if parallel)

## Opt-Out

Add `SKIP_MEMORY_EXTRACTION` on its own line in a transcript to skip extraction for that session.
Check with: `grep -qE '^SKIP_MEMORY_EXTRACTION$'`

## Condensation (Task 1)

Triggers when `grep -c '^## user'` > 20 AND filtered size > 30000 bytes.
Uses Haiku with `timeout 90`. `mkdir -p /tmp/claude` before temp file creation.

## Current Memory Stats

!`claude-memory stats 2>/dev/null || echo "(claude-memory not on PATH — run /memory-setup)"`

## MEMORY.md Format — Index-First Pattern

MEMORY.md is an **index**, not a content dump. It is always loaded into context.

**Entry types:**
- Topic file pointer: `- [Short Title](filename.md) — one-line summary` (~150 chars max)
- Inline entry: `- Terse fact or rule` (one line, no topic file needed)
- Section headers: `## Feedback`, `## Key Facts`, `## Solutions`, `## Architecture`, `## Active Projects`, `## Decisions`

**Rules:**
- Keep under 200 lines — lines after 200 are truncated in context
- Prefix critical entries with 📌 (GC never prunes pinned items)
- Replace outdated info rather than appending
- Multi-line content belongs in a topic file (with frontmatter: name, description, type)
- Mark inline content that needs migration: `(→ topic file)`
- Project memory is for YOU (future Claude), not the human
- NEVER inline topic file content back into MEMORY.md — preserve links
