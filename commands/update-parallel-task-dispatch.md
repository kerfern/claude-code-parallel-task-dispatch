---
description: Update the parallel-task-dispatch skill and this command from its GitHub source.
---

# /update-parallel-task-dispatch

Pulls the latest `parallel-task-dispatch` skill (SKILL.md + references/) and this command file
from https://github.com/kerfern/claude-code-parallel-task-dispatch.

## Workflow

1. Fetch latest files from `main` branch into a temp dir.
2. Diff against local copies; show changed line counts.
3. Nothing changed → report "already up to date" and exit.
4. Changed → ask user to confirm, then overwrite locals.

## Implementation

```bash
REPO="kerfern/claude-code-parallel-task-dispatch"
BRANCH="main"
RAW="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
API="https://api.github.com/repos/${REPO}/commits/${BRANCH}"

SKILL_DIR="$HOME/.claude/skills/parallel-task-dispatch"
SKILL_DST="$SKILL_DIR/SKILL.md"
REFS_DST="$SKILL_DIR/references"
CMD_DST="$HOME/.claude/commands/update-parallel-task-dispatch.md"

REFS="agent-prompt.md
common-mistakes.md
mcp-integration.md
worktree-mode.md
saga-rollback.md
session-persistence.md"

TMP=$(mktemp -d)
mkdir -p "$TMP/references"
trap 'rm -rf "$TMP"' EXIT

# Fetch latest
curl -fsSL "${RAW}/parallel-task-dispatch/SKILL.md"           -o "$TMP/SKILL.md"                        || { echo "FAIL: fetch SKILL.md";          exit 1; }
curl -fsSL "${RAW}/commands/update-parallel-task-dispatch.md" -o "$TMP/update-parallel-task-dispatch.md" || { echo "FAIL: fetch command file";      exit 1; }
echo "$REFS" | while IFS= read -r ref; do
  [ -z "$ref" ] && continue
  curl -fsSL "${RAW}/parallel-task-dispatch/references/${ref}" -o "$TMP/references/${ref}" || { echo "FAIL: fetch references/${ref}"; exit 1; }
done

# Latest commit info
LATEST=$(curl -fsSL "$API" 2>/dev/null | grep -E '"(sha|date)"' | head -2)

# Diff summary
SKILL_DIFF=$(diff -u "$SKILL_DST" "$TMP/SKILL.md" 2>/dev/null | grep -c '^[+-]' || true)
CMD_DIFF=$(diff -u "$CMD_DST"    "$TMP/update-parallel-task-dispatch.md" 2>/dev/null | grep -c '^[+-]' || true)
REFS_DIFF=0
REFS_COUNT=0
echo "$REFS" | while IFS= read -r ref; do
  [ -z "$ref" ] && continue
  d=$(diff -u "$REFS_DST/${ref}" "$TMP/references/${ref}" 2>/dev/null | grep -c '^[+-]' || true)
  REFS_DIFF=$((REFS_DIFF + ${d:-0}))
  REFS_COUNT=$((REFS_COUNT + 1))
done

if [ "$SKILL_DIFF" = "0" ] && [ "$CMD_DIFF" = "0" ] && [ "$REFS_DIFF" = "0" ]; then
  echo "Already up to date. ($LATEST)"
  exit 0
fi

echo "=== Changes ==="
echo "SKILL.md:          $SKILL_DIFF changed lines"
echo "update command:    $CMD_DIFF changed lines"
echo "references/:       $REFS_DIFF changed lines (across $REFS_COUNT files)"
echo "Remote head:       $LATEST"
echo ""
echo "=== SKILL.md diff (first 60 lines) ==="
diff -u "$SKILL_DST" "$TMP/SKILL.md" | head -60
```

After the user confirms:

```bash
mkdir -p "$REFS_DST"
cp "$TMP/SKILL.md"                            "$SKILL_DST"
cp "$TMP/update-parallel-task-dispatch.md"    "$CMD_DST"
echo "$REFS" | while IFS= read -r ref; do
  [ -z "$ref" ] && continue
  cp "$TMP/references/${ref}" "$REFS_DST/${ref}"
done
echo "Updated: $SKILL_DST"
echo "Updated: $CMD_DST"
echo "Updated: $REFS_DST/ ($REFS_COUNT files)"
```

If the repo adds or renames reference files, update the `REFS` array above.
The command file itself is synced, so after one update users get the new list automatically.
