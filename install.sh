#!/usr/bin/env bash
# Install the parallel-task-dispatch skill and its self-update command into ~/.claude/
# Works in two modes:
#   Local:  cd repo && ./install.sh           (uses files in the checkout)
#   Remote: curl -fsSL .../install.sh | bash  (fetches files from GitHub)
set -euo pipefail

REPO="kerfern/claude-code-parallel-task-dispatch"
BRANCH="main"
RAW="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

SKILL_DST_DIR="$HOME/.claude/skills/parallel-task-dispatch"
REFS_DST_DIR="$SKILL_DST_DIR/references"
CMD_DST_DIR="$HOME/.claude/commands"

REFS=(agent-prompt.md common-mistakes.md mcp-integration.md)

mkdir -p "$SKILL_DST_DIR" "$REFS_DST_DIR" "$CMD_DST_DIR"

# Detect mode: local (if script sits next to the repo files) or remote (via curl)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/parallel-task-dispatch/SKILL.md" ]; then
  MODE="local"
  SKILL_SRC="$SCRIPT_DIR/parallel-task-dispatch/SKILL.md"
  REFS_SRC="$SCRIPT_DIR/parallel-task-dispatch/references"
  CMD_SRC="$SCRIPT_DIR/commands/update-parallel-task-dispatch.md"

  [ -d "$REFS_SRC" ] || { echo "ERROR: missing $REFS_SRC" >&2; exit 1; }
  [ -f "$CMD_SRC" ]  || { echo "ERROR: missing $CMD_SRC"  >&2; exit 1; }

  cp "$SKILL_SRC" "$SKILL_DST_DIR/SKILL.md"
  cp "$REFS_SRC"/*.md "$REFS_DST_DIR/"
  cp "$CMD_SRC" "$CMD_DST_DIR/update-parallel-task-dispatch.md"
else
  MODE="remote"
  curl -fsSL "${RAW}/parallel-task-dispatch/SKILL.md" -o "$SKILL_DST_DIR/SKILL.md"
  for ref in "${REFS[@]}"; do
    curl -fsSL "${RAW}/parallel-task-dispatch/references/${ref}" -o "$REFS_DST_DIR/${ref}"
  done
  curl -fsSL "${RAW}/commands/update-parallel-task-dispatch.md" -o "$CMD_DST_DIR/update-parallel-task-dispatch.md"
fi

echo "Installed ($MODE):"
echo "  $SKILL_DST_DIR/SKILL.md"
echo "  $REFS_DST_DIR/*.md ($(ls "$REFS_DST_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ') files)"
echo "  $CMD_DST_DIR/update-parallel-task-dispatch.md"
echo ""
echo "Restart Claude Code, then run /update-parallel-task-dispatch to pull future updates."
