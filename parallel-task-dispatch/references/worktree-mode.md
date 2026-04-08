# Worktree Isolation Mode

Worktree mode provides physical git isolation per agent via `isolation: "worktree"`.
It is an **opt-in** mode — the default is `file-ownership-parallel`. Activate via
`--worktree` flag or by overriding at the Step C½ gate.

**When to use worktrees:**
- You are on the default branch (main/master) with a clean state
- Tasks have overlapping file ownership AND need true rollback isolation
- Critical/high-risk work where selective revert of individual agents is important

**When NOT to use worktrees:**
- Feature branch ahead of main (most common case — worktrees land on stale main)
- All tasks have disjoint files (file-ownership-parallel is simpler and faster)
- Read-only / research tasks (no writes, no isolation needed)

---

## Pre-Flight Viability Check

Claude Code's `isolation: "worktree"` creates worktrees from the repo's **default branch**
(usually `main` or `master`), NOT from the current working branch. If you're on a feature
branch, worktree agents will land on stale code and fail to implement.

```bash
CURRENT_BRANCH=$(git branch --show-current)
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
CURRENT_SHA=$(git rev-parse HEAD)
DEFAULT_SHA=$(git rev-parse origin/$DEFAULT_BRANCH 2>/dev/null || echo "unknown")
```

**Viability matrix:**

| Current branch | Branch == default? | SHAs match? | Action |
|----------------|-------------------|-------------|--------|
| main/master | Yes | — | Worktrees work normally |
| feature-branch | No | Yes (merged) | Worktrees work normally |
| feature-branch | No | **No** | Offer merge-forward OR fall back to file-ownership-parallel |

**Show viability to user before dispatch:**
```
Worktree viability: {VIABLE|NOT VIABLE}
  Current branch: {branch} ({sha[:8]})
  Default branch: {default} ({default_sha[:8]})
  Delta: {N} commits ahead

Options:
  [A] Merge-forward: ff-merge {branch} → main, push, re-check viability (RECOMMENDED)
  [B] Fall back to file-ownership-parallel (default — no worktree isolation)
  [C] Abort
```

### Path 1: Merge-forward before dispatch

Cleanest fix — after merging, `origin/main` equals the current work and worktrees
land on the correct SHA. Ask the user before doing this:

```bash
git checkout main
git merge --ff-only <feature-branch>   # fast-forward if possible; otherwise PR-merge
git push origin main
git checkout <feature-branch>          # return to feature branch
```

After merge-forward, re-run the viability check. Worktrees will be VIABLE.

**When NOT to offer merge-forward:** feature branch is WIP (tests failing, needs
review), or user explicitly wants to keep work isolated from main.

### Path 2: Fall back to file-ownership-parallel

Set `WORKTREE_VIABLE=false`. Do NOT use `isolation: "worktree"`:
- Agents implement directly on the current branch
- Strict file ownership enforcement via prompts (no physical isolation)
- Agents with OVERLAPPING owned files MUST run sequentially (separate batches)
- Agents with disjoint owned files can still run in parallel
- Read-only/research agents are unaffected

---

## Serial-Before-Parallel Invariant

**Any serial orchestrator work before a worktree dispatch must be committed and pushed
to `origin/<default_branch>` first.** Worktrees spawn from the remote default branch;
unpushed changes are invisible.

Applies at:
1. **Pre-flight** (Step 0) — initial dirty/unpushed state
2. **Between batches** (Step E BATCH GATE) — batch N's merge before batch N+1 dispatches
3. **After inline orchestrator edits** — completeness fixes, patch resolutions,
   ownership reverts, test fixes. If worktree agents follow, push first.

**Pre-dispatch check (worktree mode only):**
```bash
git status --short && git log @{u}..HEAD --oneline   # both must be empty
```
If dirty/unpushed: show diff, get user approval, commit+push, re-run viability check.

**Skip when:** file-ownership-parallel mode, serial-batches mode, config mode, or
read-only/research agents.

---

## Dispatch with Worktrees

Include `isolation: "worktree"` in the Agent call:

```
Agent(
  description="Task N: {summary}",
  prompt=AGENT_LIFECYCLE_PROMPT,
  isolation="worktree",
  model="{risk-based model from Step C}",
  run_in_background=true
)
```

**ALREADY-ON-MAIN context (mandatory for worktree agents):**
Worktree agents may land on a stale base commit. To prevent re-implementing changes
that already exist on main, include an `ALREADY ON MAIN` block when owned files were
modified in recent commits:

```markdown
**ALREADY ON MAIN (do NOT re-implement):**
- storage.py: migration 32 adds shadow_calibrated_prob column. Do NOT add again.
- strategy/ml_calibration.py: TODO block already removed in commit abc1234.
```

Generate: `git log --oneline -5 -- <owned_files>` before dispatch. If any owned file
has commits since the worktree base, add the context block.

**cwd hygiene during merge:**
After ANY command that runs in a worktree directory, the shell cwd may silently shift.
ALWAYS prefix subsequent commands with `cd /path/to/main/tree &&` to avoid running
git commands in the wrong worktree.

**Rate limits:** For 8+ parallel agents, stagger launches with 2-3s delays.

---

## Merge Protocol (Step E — Worktree Mode)

**WORKTREE BASE DRIFT CHECK (mandatory):**
Worktree branches are often created from an older ancestor, NOT from current HEAD.
Agent edits are uncommitted modifications on a stale base.

```bash
# Check EVERY worktree's HEAD before attempting merge
cd <worktree> && git log --oneline -1
```

If worktree HEAD != main HEAD (common case), use **3-way patch protocol**:

1. Create rollback tag: `git tag pre-parallel-merge-${DISPATCH_BASE_SHA:0:8}-$(date +%s)`
2. Per worktree: generate diffs for OWNED FILES ONLY:
   `cd <worktree> && git diff -- <owned_files> > /tmp/<agent>.patch`
3. Apply each patch to main tree with 3-way merge:
   `cd <main_tree> && git apply --3way /tmp/<agent>.patch`
4. Resolve conflicts: "ours" = main's newer code, "theirs" = agent's changes. Typically keep both.
5. Watch for scope mismatches: agent may reference variables/functions from old code that
   were refactored on main. Test suite catches these.

**NEVER use these when worktree HEAD != main HEAD:**
- `git merge` on worktree branch (shows "already up to date" — edits are uncommitted)
- `cp` from worktree to main (overwrites recent main-branch changes)

If worktree HEAD == main HEAD (rare), standard merge works:
1. Create rollback tag
2. Order branches by independence (zero-overlap first)
3. Per branch: ownership check → overlap check → `git merge --no-ff`

---

## Recovery from Base Drift

When a worktree agent returns with only a plan (no implementation):
- Use the agent's analysis and plan as instructions
- Implement directly on the current branch
- Do NOT re-dispatch with worktrees (same failure will repeat)
- The agent's Steps 1-3 (Analyze, Plan, Red Team) are still valuable
