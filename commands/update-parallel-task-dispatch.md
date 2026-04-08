---
description: Update the parallel-task-dispatch skill and this command from its GitHub source.
---

# /update-parallel-task-dispatch

Pulls the latest `parallel-task-dispatch` skill (SKILL.md + references/) and this command file
from https://github.com/kerfern/claude-code-parallel-task-dispatch and installs them into
`~/.claude/skills/parallel-task-dispatch/` and `~/.claude/commands/`.

## Workflow

1. Fetch latest `SKILL.md`, all `references/*.md`, and the command file from the `main` branch.
2. Diff against local copies; show a summary (total changed lines across all files).
3. If nothing changed → report "already up to date" and exit.
4. If changed → ask the user to confirm, then write the new files over the local copies.
5. Report which files were updated and the new SHA/commit date if available.

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

REFS="agent-prompt.md common-mistakes.md mcp-integration.md worktree-mode.md saga-rollback.md session-persistence.md"

TMP=$(mktemp -d)
mkdir -p "$TMP/references"
trap 'rm -rf "$TMP"' EXIT

# Fetch latest
curl -fsSL "${RAW}/parallel-task-dispatch/SKILL.md"           -o "$TMP/SKILL.md"                        || { echo "FAIL: fetch SKILL.md";          exit 1; }
curl -fsSL "${RAW}/commands/update-parallel-task-dispatch.md" -o "$TMP/update-parallel-task-dispatch.md" || { echo "FAIL: fetch command file";      exit 1; }
for ref in $REFS; do
  curl -fsSL "${RAW}/parallel-task-dispatch/references/${ref}" -o "$TMP/references/${ref}" || { echo "FAIL: fetch references/${ref}"; exit 1; }
done

# Latest commit info (best-effort)
LATEST=$(curl -fsSL "$API" 2>/dev/null | grep -E '"(sha|date)"' | head -2)

# Diff summary (grep -c always prints a number; `|| true` suppresses its exit code)
SKILL_DIFF=$(diff -u "$SKILL_DST" "$TMP/SKILL.md" 2>/dev/null | grep -c '^[+-]' || true)
CMD_DIFF=$(diff -u "$CMD_DST"    "$TMP/update-parallel-task-dispatch.md" 2>/dev/null | grep -c '^[+-]' || true)
REFS_DIFF=0
REFS_COUNT=0
for ref in $REFS; do
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
for ref in $REFS; do
  cp "$TMP/references/${ref}" "$REFS_DST/${ref}"
done
echo "Updated: $SKILL_DST"
echo "Updated: $CMD_DST"
echo "Updated: $REFS_DST/ ($REFS_COUNT files)"
```

## Repo layout expected

```
claude-code-parallel-task-dispatch/
├── README.md
├── install.sh
├── parallel-task-dispatch/
│   ├── SKILL.md
│   └── references/
│       ├── agent-prompt.md
│       ├── common-mistakes.md
│       ├── mcp-integration.md
│       ├── worktree-mode.md
│       ├── saga-rollback.md
│       └── session-persistence.md
└── commands/
    └── update-parallel-task-dispatch.md
```

If the repo adds, renames, or removes reference files, update the `REFS` array above.
The command hardcodes reference filenames for simplicity; after one successful update,
users pick up any new reference list automatically (the command file itself is synced).

## Safety

- Never auto-writes without showing diff + asking for confirmation.
- Uses `curl -fsSL` so HTTP errors surface instead of writing empty files.
- Fetches into a temp dir first; only overwrites on explicit confirmation.
- Creates `references/` directory if it doesn't exist (for upgrades from pre-references versions).
