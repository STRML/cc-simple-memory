#!/bin/bash
# Garbage-collect / consolidate MEMORY.md files using Opus.
# Prunes stale, redundant, and low-value entries. Consolidates related items.
# Pruned items go to archive files (cold storage) — never truly deleted.
# Archive is read during GC for potential promotion back to active memory.
# 📌 items are pinned and never pruned.
#
# Usage:
#   gc-memory.sh [project_dir]        # GC project + global memory
#   gc-memory.sh --dry-run [dir]      # Preview what Opus would output
#
# Called automatically by extract-learnings.sh every 10 extractions,
# or manually via: claude-memory gc

set -euo pipefail

mkdir -p /tmp/claude

LOG="/tmp/claude/extract-learnings.log"
dry_run=false
project_dir=""

for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=true ;;
    *) project_dir="$arg" ;;
  esac
done

project_dir="${project_dir:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"
encoded_path=$(echo "$project_dir" | sed 's|[/.]|-|g')
claude_project_dir="${HOME}/.claude/projects/${encoded_path}"

memory_file="${claude_project_dir}/memory/MEMORY.md"
archive_file="${claude_project_dir}/memory/ARCHIVE.md"
global_memory_file="${HOME}/.claude/rules/global-memory.md"
global_archive_file="${HOME}/.claude/memory/global-archive.md"

# Read existing memory
existing_memory=""
if [ -f "$memory_file" ] && [ -s "$memory_file" ]; then
  existing_memory=$(cat "$memory_file")
  memory_lines=$(wc -l < "$memory_file" | tr -d ' ')
else
  memory_lines=0
fi

existing_global=""
if [ -f "$global_memory_file" ] && [ -s "$global_memory_file" ]; then
  existing_global=$(cat "$global_memory_file")
  global_lines=$(wc -l < "$global_memory_file" | tr -d ' ')
else
  global_lines=0
fi

# Read archives (cold storage context for Opus)
existing_archive=""
if [ -f "$archive_file" ] && [ -s "$archive_file" ]; then
  existing_archive=$(cat "$archive_file")
  archive_lines=$(wc -l < "$archive_file" | tr -d ' ')
else
  archive_lines=0
fi

existing_global_archive=""
if [ -f "$global_archive_file" ] && [ -s "$global_archive_file" ]; then
  existing_global_archive=$(cat "$global_archive_file")
  global_archive_lines=$(wc -l < "$global_archive_file" | tr -d ' ')
else
  global_archive_lines=0
fi

# Skip if both are small enough
if [ "$memory_lines" -le 150 ] && [ "$global_lines" -le 80 ]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [GC] Skipped — project ${memory_lines} lines, global ${global_lines} lines (both under threshold)" >> "$LOG"
  if [ "$dry_run" = true ]; then
    echo "Both files under threshold (project: ${memory_lines}/150, global: ${global_lines}/80). No GC needed."
  fi
  exit 0
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [GC] Starting — project ${memory_lines} lines, global ${global_lines} lines (archives: ${archive_lines}/${global_archive_lines} lines)" >> "$LOG"

if [ "$dry_run" = true ]; then
  echo "=== Memory GC Preview ==="
  echo "Project memory:  ${memory_lines} lines (target: ≤150)"
  echo "Global memory:   ${global_lines} lines (target: ≤80)"
  echo "Project archive: ${archive_lines} lines (cold storage)"
  echo "Global archive:  ${global_archive_lines} lines (cold storage)"
  echo ""
fi

# Dedup helper: filters out lines that already exist in an archive file
dedup_against_archive() {
  local new_content="$1"
  local archive_file="$2"

  if [ ! -f "$archive_file" ] || [ ! -s "$archive_file" ]; then
    echo "$new_content"
    return
  fi

  local result=""
  while IFS= read -r line; do
    # Keep empty lines and section headers
    if [ -z "$line" ] || [[ "$line" == "##"* ]] || [[ "$line" == "###"* ]]; then
      result+="$line"$'\n'
      continue
    fi
    # Normalize: strip leading/trailing whitespace and list markers
    local normalized
    normalized=$(echo "$line" | sed 's/^[[:space:]]*[-*]*[[:space:]]*//' | sed 's/[[:space:]]*$//')
    # Skip if too short to meaningfully match
    if [ ${#normalized} -lt 15 ]; then
      result+="$line"$'\n'
      continue
    fi
    # Check if this content already exists in archive
    if ! grep -qF "$normalized" "$archive_file" 2>/dev/null; then
      result+="$line"$'\n'
    fi
  done <<< "$new_content"

  # Remove trailing newline
  echo "${result%$'\n'}"
}

cd "$project_dir" 2>/dev/null || cd "$HOME"

output=$(CLAUDE_CODE_SIMPLE=1 claude -p --model opus --effort low --no-session-persistence \
  --tools "" \
  --disable-slash-commands \
  --strict-mcp-config \
  --settings '{"disableAllHooks":true}' \
  --system-prompt "You are a memory curator. You CONSOLIDATE, PRUNE, and PROMOTE.

## MEMORY.md FORMAT — INDEX-FIRST PATTERN (CRITICAL)

MEMORY.md is an INDEX, not a content dump. It is always loaded into Claude's context window.

**Topic file links** like \`- [Title](filename.md) — summary\` point to separate files on disk. You MUST:
- PRESERVE all topic file links exactly (filename, title, summary)
- NEVER inline the content of a linked topic file
- You may update the summary text after \`—\` if it's stale
- You may archive a topic file link if the content is clearly obsolete (but archive the link, not the file content)

**Inline entries** (no link) can be consolidated, pruned, or archived normally.

## Rules

### Project memory pins
- 📌 items in PROJECT memory are pinned. Never prune, never archive. Copy them through unchanged.

### Global memory pins — DIFFERENT RULES
- 📌 items in GLOBAL memory CAN be demoted (pin removed) or archived if they are project-specific.
- The global file is badly over-pinned. Most items should NOT be pinned in global.
- Only keep 📌 in global for truly universal patterns (e.g., Claude Code sandbox behavior, basic Docker commands).
- Project-specific items (WordPress, CRM APIs, domain tooling, specific frameworks) should be ARCHIVED from global even if pinned. They belong in project memory, not global.

### General rules
- Items you remove from active memory MUST go to the newly archived section — never delete outright.
- Read the archive for context. If an archived item is clearly still relevant to the current project, promote it back into active memory (without the archive timestamp).
- Don't promote aggressively — only items that would save significant time if forgotten.

## Output Format

Output four sections separated by delimiters. No preamble, no explanation, no markdown fences around the whole output.

<updated project memory>
---GLOBAL_MEMORY_SEPARATOR---
<updated global memory>
---PROJECT_ARCHIVE_SEPARATOR---
<items pruned from project memory this pass>
---GLOBAL_ARCHIVE_SEPARATOR---
<items pruned from global memory this pass>

If no items were pruned from a section, output (empty) after that separator.

## Targets

- Project memory: ≤150 lines (hard cap: 200)
- Global memory: ≤50 lines (hard cap: 80). This is a SMALL file — be ruthless.
- In PROJECT memory, 📌 items don't count toward targets.
- In GLOBAL memory, 📌 items DO count toward the 50-line target. Remove pins from project-specific items.
- Topic file links are compact (1 line each) and count toward line targets, but prefer keeping them over inline content.

## What to PRUNE from global (move to archive)

- Project-specific items: WordPress, WooCommerce, Freshsales, Make.com, tmux, specific API details — these are project knowledge, not global
- Redundant entries: multiple entries saying the same thing
- Overly specific details: exact file paths, line numbers, variable names
- One-time fixes that won't recur in other projects
- Obvious patterns any experienced developer would know
- Implementation details better found by reading docs
- Items that only applied to one project context

## What to KEEP in global

- Claude Code behavioral quirks (sandbox, hooks, background tasks)
- Universal Docker/Git/CI patterns that bite everyone
- Cross-cutting dev patterns (error handling, testing, debugging)
- User workflow preferences (commit style, tool choices)
- Keep entries TERSE — one line each, no verbose explanations

## What to PRUNE from project memory

- Redundant entries
- Stale information about changed code
- Duplicates of what's already in global
- Obvious patterns
- Verbose inline content that could be one line (consolidate it)

### Archive deduplication
- Do NOT include items in the archive output that already appear in the archive input. The archive is append-only — re-archiving duplicates wastes space.
- If an item in active memory duplicates something already archived, remove it from active memory WITHOUT adding it to the archive output sections.

## What to KEEP in project memory

- ALL topic file links \`[Title](file.md)\` — these are compact pointers, always preserve
- Genuinely surprising gotchas for this specific project
- API quirks, data format details, environment setup
- Patterns that apply repeatedly in this codebase
- Debugging insights specific to this project's stack
- Any 📌 item (unconditionally in project memory)
- The \`## Decisions\` section — keep the 3-5 most recent/relevant decisions. Older decisions can be removed from MEMORY.md (they live in the append-only decision log). Always preserve the pinned line: \`📌 Full decision log: memory/DECISIONS.md\`

## How to consolidate

- Merge related entries under shared headers
- Compress verbose inline content into terse one-liners (~150 chars)
- Multi-line inline content that can't be compressed → mark with \`(→ topic file)\` for later migration
- Remove examples when the rule is self-explanatory
- Prefer 'Do X' over 'When Y happens, you should do X because Z'
- NEVER expand topic file links into inline content — that's the opposite of consolidation" \
  "PROJECT MEMORY.MD (${memory_lines} lines — target ≤150):
${existing_memory:-<empty>}

---

GLOBAL MEMORY (${global_lines} lines — target ≤80):
${existing_global:-<empty>}

---

PROJECT ARCHIVE (cold storage — ${archive_lines} lines, review for promotions):
${existing_archive:-<empty — no archived items yet>}

---

GLOBAL ARCHIVE (cold storage — ${global_archive_lines} lines, review for promotions):
${existing_global_archive:-<empty — no archived items yet>}

---

Consolidate and prune both active memory files. Move pruned items to the archive sections. Promote archived items back if they're clearly still relevant. Output all four sections." 2>&1)

if [ "$dry_run" = true ]; then
  echo "=== Opus Output ==="
  echo "$output"
  exit 0
fi

timestamp=$(date '+%Y-%m-%d %H:%M:%S')

if [ -n "$output" ] && [ ${#output} -gt 50 ]; then
  # Split output into 4 sections
  # 1: project memory (before GLOBAL_MEMORY_SEPARATOR)
  # 2: global memory (between GLOBAL_MEMORY_SEPARATOR and PROJECT_ARCHIVE_SEPARATOR)
  # 3: project archive additions (between PROJECT_ARCHIVE_SEPARATOR and GLOBAL_ARCHIVE_SEPARATOR)
  # 4: global archive additions (after GLOBAL_ARCHIVE_SEPARATOR)

  project_part=$(echo "$output" | sed -n '1,/---GLOBAL_MEMORY_SEPARATOR---/p' | sed '$d')
  rest_after_global_sep=$(echo "$output" | sed -n '/---GLOBAL_MEMORY_SEPARATOR---/,$p' | sed '1d')
  global_part=$(echo "$rest_after_global_sep" | sed -n '1,/---PROJECT_ARCHIVE_SEPARATOR---/p' | sed '$d')
  rest_after_proj_archive=$(echo "$rest_after_global_sep" | sed -n '/---PROJECT_ARCHIVE_SEPARATOR---/,$p' | sed '1d')
  project_archive_new=$(echo "$rest_after_proj_archive" | sed -n '1,/---GLOBAL_ARCHIVE_SEPARATOR---/p' | sed '$d')
  global_archive_new=$(echo "$rest_after_proj_archive" | sed -n '/---GLOBAL_ARCHIVE_SEPARATOR---/,$p' | sed '1d')

  # Write updated project memory
  if [ -n "$project_part" ] && [ ${#project_part} -gt 50 ]; then
    new_lines=$(echo "$project_part" | wc -l | tr -d ' ')
    echo "$project_part" > "$memory_file"
    echo "[$timestamp] [GC] Project memory: ${memory_lines} → ${new_lines} lines" >> "$LOG"
  fi

  # Write updated global memory
  if [ -n "$global_part" ] && [ ${#global_part} -gt 50 ]; then
    new_lines=$(echo "$global_part" | wc -l | tr -d ' ')
    mkdir -p "$(dirname "$global_memory_file")"
    echo "$global_part" > "$global_memory_file"
    echo "[$timestamp] [GC] Global memory: ${global_lines} → ${new_lines} lines" >> "$LOG"
  fi

  # Append newly archived project items (deduped against existing archive)
  project_archive_trimmed=$(echo "$project_archive_new" | sed '/^[[:space:]]*$/d' | grep -vi '(empty)' || true)
  if [ -n "$project_archive_trimmed" ] && [ ${#project_archive_trimmed} -gt 10 ]; then
    project_archive_trimmed=$(dedup_against_archive "$project_archive_trimmed" "$archive_file")
    # Re-check after dedup — may have removed everything
    project_archive_trimmed=$(echo "$project_archive_trimmed" | sed '/^[[:space:]]*$/d')
    if [ -n "$project_archive_trimmed" ] && [ ${#project_archive_trimmed} -gt 10 ]; then
      mkdir -p "$(dirname "$archive_file")"
      {
        echo ""
        echo "## Archived ${timestamp}"
        echo ""
        echo "$project_archive_trimmed"
      } >> "$archive_file"
      new_archive_lines=$(echo "$project_archive_trimmed" | wc -l | tr -d ' ')
      echo "[$timestamp] [GC] Archived ${new_archive_lines} lines to project archive" >> "$LOG"
    else
      echo "[$timestamp] [GC] All project archive items were duplicates — skipped" >> "$LOG"
    fi
  fi

  # Append newly archived global items (deduped against existing archive)
  global_archive_trimmed=$(echo "$global_archive_new" | sed '/^[[:space:]]*$/d' | grep -vi '(empty)' || true)
  if [ -n "$global_archive_trimmed" ] && [ ${#global_archive_trimmed} -gt 10 ]; then
    global_archive_trimmed=$(dedup_against_archive "$global_archive_trimmed" "$global_archive_file")
    # Re-check after dedup — may have removed everything
    global_archive_trimmed=$(echo "$global_archive_trimmed" | sed '/^[[:space:]]*$/d')
    if [ -n "$global_archive_trimmed" ] && [ ${#global_archive_trimmed} -gt 10 ]; then
      mkdir -p "$(dirname "$global_archive_file")"
      {
        echo ""
        echo "## Archived ${timestamp}"
        echo ""
        echo "$global_archive_trimmed"
      } >> "$global_archive_file"
      new_archive_lines=$(echo "$global_archive_trimmed" | wc -l | tr -d ' ')
      echo "[$timestamp] [GC] Archived ${new_archive_lines} lines to global archive" >> "$LOG"
    else
      echo "[$timestamp] [GC] All global archive items were duplicates — skipped" >> "$LOG"
    fi
  fi
else
  echo "[$timestamp] [GC] Failed — no output or too short (${#output:-0} bytes)" >> "$LOG"
fi
