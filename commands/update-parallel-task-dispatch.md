---
description: Update the parallel-task-dispatch skill and this command from its GitHub source.
---

# /update-parallel-task-dispatch

Pulls the latest `parallel-task-dispatch` skill (and this command file) from
https://github.com/kerfern/claude-code-parallel-task-dispatch and installs them into
`~/.claude/skills/parallel-task-dispatch/` and `~/.claude/commands/`.

## Workflow

1. Fetch latest `SKILL.md` and `commands/update-parallel-task-dispatch.md` from the `main` branch into a temp dir.
2. Diff against the local copies; show a summary (lines added/removed, new section headings).
3. If nothing changed → report "already up to date" and exit.
4. If changed → ask the user to confirm, then write the new files over the local copies.
5. Report which files were updated and the new SHA/commit date if available.

## Implementation

```bash
REPO="kerfern/claude-code-parallel-task-dispatch"
BRANCH="main"
RAW="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
API="https://api.github.com/repos/${REPO}/commits/${BRANCH}"

SKILL_DST="$HOME/.claude/skills/parallel-task-dispatch/SKILL.md"
CMD_DST="$HOME/.claude/commands/update-parallel-task-dispatch.md"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Fetch latest
curl -fsSL "${RAW}/parallel-task-dispatch/SKILL.md"           -o "$TMP/SKILL.md"                        || { echo "FAIL: fetch SKILL.md";          exit 1; }
curl -fsSL "${RAW}/commands/update-parallel-task-dispatch.md" -o "$TMP/update-parallel-task-dispatch.md" || { echo "FAIL: fetch command file";      exit 1; }

# Latest commit info (best-effort)
LATEST=$(curl -fsSL "$API" 2>/dev/null | grep -E '"(sha|date)"' | head -2)

# Diff summary
SKILL_DIFF=$(diff -u "$SKILL_DST" "$TMP/SKILL.md" 2>/dev/null | grep -c '^[+-]' || echo 0)
CMD_DIFF=$(diff -u "$CMD_DST"    "$TMP/update-parallel-task-dispatch.md" 2>/dev/null | grep -c '^[+-]' || echo 0)

if [ "$SKILL_DIFF" = "0" ] && [ "$CMD_DIFF" = "0" ]; then
  echo "Already up to date. ($LATEST)"
  exit 0
fi

echo "=== Changes ==="
echo "SKILL.md:          $SKILL_DIFF changed lines"
echo "update command:    $CMD_DIFF changed lines"
echo "Remote head:       $LATEST"
echo ""
echo "=== SKILL.md diff (first 60 lines) ==="
diff -u "$SKILL_DST" "$TMP/SKILL.md" | head -60
```

After the user confirms:

```bash
cp "$TMP/SKILL.md"                       "$SKILL_DST"
cp "$TMP/update-parallel-task-dispatch.md"    "$CMD_DST"
echo "Updated: $SKILL_DST"
echo "Updated: $CMD_DST"
```

## Repo layout expected

```
claude-code-parallel-task-dispatch/
├── README.md
├── install.sh
├── parallel-task-dispatch/
│   └── SKILL.md
└── commands/
    └── update-parallel-task-dispatch.md
```

If the repo ever renames files or changes the branch, update `REPO` / `BRANCH` / paths above.

## Safety

- Never auto-writes without showing diff + asking for confirmation.
- Uses `curl -fsSL` so HTTP errors surface instead of writing empty files.
- Fetches into a temp dir first; only overwrites on explicit confirmation.
