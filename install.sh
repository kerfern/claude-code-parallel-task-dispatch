#!/usr/bin/env bash
# Install the parallel-task-dispatch skill and its self-update command into ~/.claude/
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_SRC="$REPO_DIR/parallel-task-dispatch/SKILL.md"
CMD_SRC="$REPO_DIR/commands/update-parallel-task-dispatch.md"

SKILL_DST_DIR="$HOME/.claude/skills/parallel-task-dispatch"
CMD_DST_DIR="$HOME/.claude/commands"

# Verify sources exist
[ -f "$SKILL_SRC" ] || { echo "ERROR: missing $SKILL_SRC" >&2; exit 1; }
[ -f "$CMD_SRC" ]   || { echo "ERROR: missing $CMD_SRC"   >&2; exit 1; }

mkdir -p "$SKILL_DST_DIR" "$CMD_DST_DIR"

cp "$SKILL_SRC" "$SKILL_DST_DIR/SKILL.md"
cp "$CMD_SRC"   "$CMD_DST_DIR/update-parallel-task-dispatch.md"

echo "Installed:"
echo "  $SKILL_DST_DIR/SKILL.md"
echo "  $CMD_DST_DIR/update-parallel-task-dispatch.md"
echo ""
echo "Restart Claude Code, then run /update-parallel-task-dispatch to pull future updates."
