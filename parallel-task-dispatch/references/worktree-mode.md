# Worktree Isolation Mode

Opt-in via `--worktree`. Default is `file-ownership-parallel`.

## Pre-Flight Viability Check

`isolation: "worktree"` creates worktrees from the **default branch** (main/master), NOT the current branch. Feature-branch worktrees land on stale code.

```bash
CURRENT_BRANCH=$(git branch --show-current)
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
CURRENT_SHA=$(git rev-parse HEAD)
DEFAULT_SHA=$(git rev-parse origin/$DEFAULT_BRANCH 2>/dev/null || echo "unknown")
```

| Current branch | SHAs match? | Action |
|----------------|-------------|--------|
| main/master | — | Worktrees viable |
| feature (merged to main) | Yes | Worktrees viable |
| feature (not merged) | **No** | Merge-forward OR fall back |

### Merge-forward

Ask user first. After merge, worktrees land on correct SHA:

```bash
git checkout main && git merge --ff-only <feature-branch> && git push origin main && git checkout <feature-branch>
```

Skip if: feature is WIP (tests failing, needs review) or user wants isolation from main.

### Fall back to file-ownership-parallel

No `isolation: "worktree"`. Strict prompt-based ownership. Overlapping files → sequential batches. Disjoint files → parallel. Research agents unaffected.

---

## Serial-Before-Parallel Invariant

Any serial orchestrator work before worktree dispatch must be committed and pushed to `origin/<default>`. Worktrees spawn from the remote default branch; unpushed changes are invisible.

Applies at: pre-flight (Step 0), between batches (Step E), after inline orchestrator edits.

```bash
git status --short && git log @{u}..HEAD --oneline   # both must be empty
```

Skip when: file-ownership-parallel, serial-batches, config mode, or research agents.

---

## Dispatch

Include `isolation: "worktree"` in Agent call. Mandatory additions:

**ALREADY-ON-MAIN context** — prevent re-implementing existing changes:

```markdown
**ALREADY ON MAIN (do NOT re-implement):**
- storage.py: migration 32 adds shadow_calibrated_prob column
- strategy/ml_calibration.py: TODO block removed in commit abc1234
```

Generate from `git log --oneline -5 -- <owned_files>`. Include if any owned file has recent commits.

**cwd hygiene**: after worktree commands, prefix subsequent commands with `cd /path/to/main/tree &&`.

**Rate limits**: 8+ agents → stagger launches 2-3s.

---

## Merge Protocol (3-way patch)

Worktree HEAD often != main HEAD. Agent edits are uncommitted on a stale base.

1. Create rollback tag: `git tag pre-parallel-merge-${DISPATCH_BASE_SHA:0:8}-$(date +%s)`
2. Per worktree, generate diffs for OWNED FILES ONLY:
   `cd <worktree> && git diff -- <owned_files> > /tmp/<agent>.patch`
3. Apply to main: `cd <main_tree> && git apply --3way /tmp/<agent>.patch`
4. Conflicts: "ours" = main's newer code, "theirs" = agent's changes. Typically keep both.

If worktree HEAD == main HEAD (rare): standard `git merge --no-ff` works.

---

## Recovery from Base Drift

When a worktree agent returns with only a plan:
- Use the agent's analysis and plan as instructions
- Implement directly on the current branch
- Do NOT re-dispatch (same failure will repeat)
