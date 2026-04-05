---
name: parallel-task-dispatch
description: Use when you have a task list file with 2+ tasks to implement in parallel. Each agent runs a full 6-step lifecycle (analyze, plan, red-team, implement, test, report). Orchestrator handles dependency graphs, file ownership, model routing, merge/reconcile, task file updates, and commit+push. Supports claims-based work stealing, team presets, eval-first gates, risk scoring, session persistence, and saga rollback. Auto-detects git worktree vs config mode. Triggers on "run tasks in parallel", "dispatch task list", "work through issues list". Not for single tasks.
---

# Parallel Task Dispatch

**Source:** https://github.com/kerfern/claude-code-parallel-task-dispatch — run `/update-parallel-task-dispatch` to pull the latest version.

## Architecture

Three layers — **orchestrator** (you), **agents** (per-task), and **coordination** (MCP-backed):

```
ORCHESTRATOR (shared state)          AGENTS (per-task, isolated)
================================     ================================
0. Pre-flight — clean tree,          1. Analyze — read issue, check
   commit + push, resume session        depends/blocks, verify facts
A. Parse task file + risk score      2. Plan — files/changes, order,
B. Build dependency graph               verification, edge cases
C. Assign file ownership + model     3. Red team — challenge plan,
C½. Worktree necessity check            verify assumptions
D. Dispatch parallel batches    →    4. Implement — write code/config
D½. Monitor + rebalance        ↔     5. Test — eval-first gates
E. Merge/validate results     ←     6. Report — structured output
F. Bookkeep task file + learn           for orchestrator steps E-G
G. Commit + push + persist

         COORDINATION (MCP-backed, optional)
         ====================================
         Claims — work-stealing queue
         Hive-mind — shared memory + consensus
         Model routing — sonnet/opus
         Progress — real-time tracking
         Learning — SONA trajectories
```

**Steps 1-6 are per-agent.** Each agent runs the full lifecycle autonomously in its worktree/context. The orchestrator never implements — it coordinates.

### Execution Modes (auto-detected)

| Mode | When | Isolation | Rollback |
|------|------|-----------|----------|
| **Git** | Target files in a git repo | `isolation: "worktree"` | `git tag` + `git reset` |
| **Config** | Files outside git (`~/.claude/`) | File ownership only | Timestamped backups |

### Capability Layers

The skill has a **core layer** (always active) and **enhancement layers** (activated when
MCP tools are available or task complexity warrants them). Never skip core for enhancements.

| Layer | Steps | Requires | Default |
|-------|-------|----------|---------|
| **Core** | 0, A, B, C, C½, D-G + Agent 1-6 | Claude Code Task tool | Always on |
| **Worktree necessity check** | C½ | — | On — selects execution mode (user-overridable) |
| **Serial-Before-Parallel Invariant** | 0, E BATCH GATE, all pre-worktree dispatches | — | On — worktree-mode only |
| **Model routing** | C, D | — | On (built into agent params) |
| **Risk scoring** | A, C | — | On (keyword heuristic) |
| **Eval-first gates** | Agent 4 | — | On (tests before + after) |
| **Claims & rebalance** | D½ | `mcp__claude-flow__claims_*` | Off — activate for 6+ agents |
| **Progress tracking** | D½ | `mcp__claude-flow__progress_*` | Off — activate for 3+ batches |
| **Hive-mind shared memory** | D, E | `mcp__claude-flow__hive-mind_*` | Off — activate for cross-agent state |
| **Session persistence** | 0, G | `mcp__claude-flow__session_*` | Off — activate for multi-hour runs |
| **Learning loop** | F, G | `mcp__claude-flow__hooks_intelligence_*` | Off — activate to improve future routing |

---

## Team Presets

For common task shapes, use a preset instead of building from scratch. Presets set
agent types, model tiers, and team composition automatically.

| Preset | Agents | Topology | When to Use |
|--------|--------|----------|-------------|
| **feature** | 1 lead + 2-3 implementers | hierarchical | Multi-file feature implementation |
| **review** | 3-5 parallel reviewers | flat | Security + performance + architecture audit |
| **debug** | 3 parallel debuggers | flat (ACH) | Complex bug with multiple hypotheses |
| **fullstack** | frontend + backend + API + test | hierarchical | Cross-layer feature |
| **migration** | 2 implementers + 1 reviewer | pipeline | Framework upgrade, API version bump |
| **research** | 3-5 Explore agents | flat | Investigation, audit, data analysis |

**To use a preset**, add `preset: feature` (or similar) to your dispatch invocation.
The orchestrator fills in agent types, model tiers, and file ownership rules per the table.
You can override any field.

---

## Orchestrator Step 0 — PRE-FLIGHT

**Why:** Worktrees are created from the repo's **default branch** (usually `main`), NOT from
the current working branch. Uncommitted changes AND feature-branch commits are invisible
to worktree agents. This is the #1 cause of worktree agent failure.

**Session resume check (if session persistence enabled):**
```
If mcp__claude-flow__session_* available:
  Check for saved dispatch session → offer to resume from last checkpoint
  If resuming: skip to the batch that was in progress, re-dispatch incomplete tasks
```

**Run these checks in parallel:**

```bash
git status --short                    # uncommitted changes?
git log @{u}..HEAD --oneline 2>&1    # unpushed commits?
git diff --stat                       # unstaged changes?
```

**Decision matrix:**

| Uncommitted changes? | Unpushed commits? | Action |
|----------------------|-------------------|--------|
| No | No | Proceed to Step A |
| Yes | — | **STOP.** Show `git status` to user. Ask: "Commit these changes before parallel dispatch?" If yes, stage relevant files, commit, then re-check. If no, abort. |
| — | Yes | **STOP.** Show unpushed commits to user. Ask: "Push to remote before parallel dispatch?" If yes, `git push`. If no, warn that worktree agents will have these commits but remote won't — proceed with caution. |

**Rules:**
- NEVER auto-commit — always show the diff and ask the user
- NEVER auto-push — always confirm with the user first
- If the user says "commit and push", do both then re-verify clean state
- If there are untracked files the user doesn't want to commit, that's fine — only tracked modifications matter for worktree correctness
- Config mode (files outside git) skips git checks entirely

**After clean state confirmed**, record the baseline:
```bash
git rev-parse HEAD   # save as DISPATCH_BASE_SHA for rollback reference
```

**CRITICAL — Feature-branch worktree viability check:**

Claude Code's `isolation: "worktree"` creates worktrees from the repo's **default branch**
(usually `main` or `master`), NOT from the current working branch. If you're on a feature
branch, worktree agents will land on stale code and fail to implement.

```bash
CURRENT_BRANCH=$(git branch --show-current)
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
CURRENT_SHA=$(git rev-parse HEAD)
DEFAULT_SHA=$(git rev-parse origin/$DEFAULT_BRANCH 2>/dev/null || echo "unknown")
```

**Worktree viability matrix:**

| Current branch | Branch == default? | SHAs match? | Action |
|----------------|-------------------|-------------|--------|
| main/master | Yes | — | Worktrees work normally |
| feature-branch | No | Yes (merged) | Worktrees work normally |
| feature-branch | No | **No** | Offer user merge-forward (recommended) OR direct-implementation fallback |

**When the feature branch is ahead of default — two paths:**

### Path 1 (RECOMMENDED): Merge-forward before dispatch

This is the cleanest fix and matches standard Git flow. After merging the feature
branch forward, `origin/main` equals the current work and worktrees land on the
correct SHA. Ask the user before doing this:

```bash
git checkout main
git merge --ff-only <feature-branch>   # fast-forward if possible; otherwise PR-merge
git push origin main
git checkout <feature-branch>          # return to feature branch for the dispatch
# (optional) git branch -d <feature-branch>  if it's now redundant
```

After merge-forward, re-run the viability check — worktrees will be VIABLE and you
can dispatch with `isolation: "worktree"` for true parallel isolation.

**Offer this as the first option whenever feature-branch is ahead of default.**
It converts the dispatch from "no-isolation sequential-for-overlaps" back into
"full-worktree true-parallel" — which is the entire point of this skill.

**When NOT to offer merge-forward:** the feature branch is not ready to land
(tests failing, WIP, needs review), OR the user has explicitly said they want
to keep work isolated from main. In those cases fall through to Path 2.

### Path 2 (FALLBACK): Direct implementation without worktrees

Set `WORKTREE_VIABLE=false`. For ALL code-modifying tasks in this dispatch:
- Do **NOT** use `isolation: "worktree"` — agents implement directly on the current branch
- Dispatch agents WITHOUT isolation but WITH strict file ownership enforcement
- Agents with OVERLAPPING owned files MUST run sequentially (separate batches)
- Agents with disjoint owned files can still run in parallel in one batch
- Read-only/research agents can still run in parallel (no worktree needed)

**Show the viability check result to the user before dispatch:**
```
Worktree viability: {VIABLE|NOT VIABLE}
  Current branch: {branch} ({sha[:8]})
  Default branch: {default} ({default_sha[:8]})
  Delta: {N} commits ahead

Options:
  [A] Merge-forward: ff-merge {branch} → main, push, re-check viability (RECOMMENDED)
  [B] Direct implementation: dispatch without worktree isolation (fallback)
  [C] Abort
```

## Serial-Before-Parallel Invariant

**Any serial orchestrator work before a worktree dispatch must be committed and pushed
to `origin/<default_branch>` first.** Worktrees spawn from the remote default branch;
unpushed changes are invisible. Root cause of "agent only planned" and "agent re-added
something already on main."

Applies at:
1. **Pre-flight** (Step 0) — initial dirty/unpushed state.
2. **Between batches** (Step E BATCH GATE) — batch N's merge before batch N+1 dispatches.
3. **After inline orchestrator edits** — completeness fixes, patch resolutions,
   ownership reverts, test fixes. If worktree agents follow, push first.

**Pre-dispatch check (worktree isolation only):**
```bash
git status --short && git log @{u}..HEAD --oneline   # both must be empty
```
If dirty/unpushed: show diff, get user approval (same policy as Step 0), commit+push,
re-run Step 0 viability check, then dispatch.

**Skip when:** read-only/research agents, config mode, or execution mode is `file-ownership-parallel` or `serial-batches` (no worktrees used).

## Orchestrator Step A — PARSE + RISK SCORE

Read the task list file. Extract per task:

| Field | Look for | Effect |
|-------|---------|--------|
| Depends on | `depends on: #N`, `after: #N`, `requires: #N` (first match wins) | Cannot start until dependency completes |
| Blocks | `blocks: #N`, `before: #N` | Dependents wait |
| Priority | `P0/P1/P2`, `priority: high/med/low` | Order within batch |
| Status | `[x]`, `DONE`, `CLOSED` | Skip |

**Risk scoring (per task):**

Assign a risk tier based on task content. This drives model selection and review gates.

| Risk Tier | Keywords / Signals | Model | Review Gate |
|-----------|-------------------|-------|-------------|
| **Critical** | "auth", "payment", "credential", "secret", "trading", "order", "financial" | opus or sonnet | Mandatory security-reviewer post-merge |
| **High** | "migration", "schema", "delete", "remove", "refactor", "breaking" | sonnet | Full test suite + diff review |
| **Standard** | Implementation, feature, bugfix | sonnet | Standard batch gate |
| **Low** | "docs", "comment", "readme", "typo", "config" | sonnet | Minimal — ownership check only |
| **Research** | "investigate", "audit", "analyze", "measure", "benchmark" | sonnet (Explore agent) | No merge — report only |

## Orchestrator Step B — DEPENDENCY GRAPH

- Topological sort tasks into parallel batches
- Batch 1: no dependencies (run in parallel)
- Batch 2: depends on Batch 1 results (run after Batch 1 merges)
- Circular dependencies: if topological sort fails, show cycle to user ("Tasks #A -> #B -> #C -> #A"), ask which edge to remove, re-sort, verify. If user declines, abort.

**Critical-path highlight:** Identify the longest dependency chain. Show it in the execution
plan so the user knows which tasks are on the critical path (delay = overall delay).

## Orchestrator Step C — FILE OWNERSHIP + MODEL ROUTING

Per task, identify target files (from description or grep/glob). Build ownership matrix — one owner per file. Present execution plan:

```
EXECUTION PLAN
==============
Batch 1 (parallel): #1[sonnet], #3[sonnet], #5[sonnet/explore]
Batch 2 (after #1):  #2[sonnet] (depends on #1)

| # | Task | Batch | Risk | Model | Agent Type | Owned Files | Read-Only |
|---|------|-------|------|-------|------------|-------------|-----------|
| 1 | Add auth | 1 | Critical | sonnet | general | src/auth.py | src/config.py |
| 3 | Fix typo | 1 | Low | sonnet | general | docs/api.md | — |
| 5 | Audit perf | 1 | Research | sonnet | Explore | — (read-only) | src/**/*.py |
| 2 | Rate limit | 2 | High | sonnet | general | src/middleware.py | src/auth.py |
```

**Overlap detection:** If a file appears in 2+ tasks within the same batch, assign to higher-priority task; other gets read-only. If both MUST write, split into sequential batches.

**Migration number coordination:** If multiple tasks add database migrations, pre-assign
migration numbers in the execution plan based on the current schema version. Tell each
agent its assigned number explicitly (e.g., "You are adding migration 33. Do NOT use any
other number."). Check current version: `grep -c '_migrate_' storage.py` or equivalent.

**Research-only agents:** Tasks that only need code reading (audits, investigations,
data queries) should be dispatched WITHOUT `isolation: "worktree"`. This avoids base
drift entirely and runs faster. Only use worktree isolation for agents that modify files.

**Model routing rules:**

| Agent Role | Default Model | Override When |
|-----------|--------------|---------------|
| Implementation (write code) | `model: "sonnet"` | Critical risk → omit (use default opus/sonnet) |
| Research / read-only | `model: "sonnet"` | — |
| Review / security audit | `model: "sonnet"` | — |
| Test writing | `model: "sonnet"` | — |
| Documentation | `model: "sonnet"` | — |

Sonnet is the default for all agent roles. Use opus only when explicitly needed for
complex architectural reasoning or security-critical code review.

**User approves before dispatch.**

## Worktree Necessity Check

**Worktrees add overhead** — commit+push cycles, base-drift risk, merge reconciliation.
Before defaulting to `isolation: "worktree"`, check whether the tasks actually need
physical isolation. Evaluated after Step C (file ownership known):

| File overlap? | Risk tier | Execution mode |
|---------------|-----------|----------------|
| None (disjoint) | Standard/Low/Research | **`file-ownership-parallel`** — no worktrees |
| None (disjoint) | Critical/High | **`worktree-parallel`** — isolation for rollback |
| Overlap + worktrees viable | Any | **`worktree-parallel`** — prevents races |
| Overlap + worktrees NOT viable | Any | **`serial-batches`** — split overlaps sequentially |

**`file-ownership-parallel`**: all owned-file sets disjoint AND no critical/high-risk work
(trading, auth, migrations, schema). Fastest path — skips worktree setup entirely; no
Serial-Before-Parallel Invariant applies.

**`worktree-parallel`**: file overlap requires physical isolation OR critical/high-risk
work needs clean rollback. Requires `WORKTREE_VIABLE=true` from Step 0.

**`serial-batches`**: overlap exists AND worktrees not viable. Step B splits overlapping
tasks across sequential batches; disjoint tasks in each batch still run in parallel with
file ownership.

Show the mode before dispatch with override options:
```
Execution mode: {file-ownership-parallel | worktree-parallel | serial-batches}
  Reason: {disjoint + standard risk | overlap + viable | overlap + feature branch}
  Override:
    [A] Accept (proceed to Step D)
    [B] Force worktree-parallel    (requires WORKTREE_VIABLE=true)
    [C] Force file-ownership-parallel (skips worktrees even on critical/high risk)
    [D] Abort dispatch
```

User can override when risk tolerance differs from the heuristic — paranoid on
migrations → force worktree; time-sensitive non-critical → force file-ownership.
Default: accept. Option [B] is unavailable when `WORKTREE_VIABLE=false`.
Option [C] with overlap requires re-running Step B/C to split overlapping tasks
into sequential batches.

Step D's `isolation: "worktree"` flag uses the final (post-override) mode.

## Orchestrator Step D — DISPATCH

**All agents in a batch dispatched in ONE message.** Each agent receives the full 6-step lifecycle in its prompt.
**Dispatch mode is set by the Worktree Necessity Check** (`worktree-parallel` | `file-ownership-parallel` | `serial-batches`).

### Git Mode

```
Agent(
  description="Task N: {summary}",
  prompt=AGENT_LIFECYCLE_PROMPT,
  isolation="worktree",    # ONLY include when execution mode is `worktree-parallel` AND WORKTREE_VIABLE=true
  model="{risk-based model from Step C}",
  run_in_background=true
)
```

Drop `isolation="worktree"` when execution mode is `file-ownership-parallel` or
`serial-batches`. **Without isolation, file overlap is dangerous** — Step B/C must
have already split overlapping owned files into separate sequential batches.

### Config Mode

```
Agent(
  description="Task N: {summary}",
  prompt=AGENT_LIFECYCLE_PROMPT,
  model="{risk-based model from Step C}",
  run_in_background=true
)
```

**STOP after dispatch.** Wait for all agents in the batch to return.

**Post-dispatch validation (MANDATORY for worktree agents):**
When an agent returns, check its result for signs of worktree base drift:
1. Agent only planned but didn't implement → **BASE DRIFT.** Implement directly.
2. Agent reports `status: blocked` with "dependency missing" → likely base drift
3. Worktree was cleaned up with no changes persisted → agent didn't write code
4. Agent's worktree HEAD doesn't match DISPATCH_BASE_SHA → stale base

**Recovery from base drift (switch to `file-ownership-parallel`):**
If worktree agents fail due to base drift, do NOT re-dispatch with worktrees.
Instead, use the agent's PLAN output as instructions and implement directly on
the current branch. The agent's analysis + plan (Steps 1-3) are still valuable
even when implementation (Step 4) failed.

**ALREADY-ON-MAIN context (mandatory for worktree agents when viable):**
Worktree agents may land on a stale base commit (see Step E). To prevent agents from
re-implementing changes that already exist on main, include an `ALREADY ON MAIN` block
in each agent's prompt when their owned files were modified in recent commits:

```markdown
**ALREADY ON MAIN (do NOT re-implement):**
- storage.py: migration 32 adds shadow_calibrated_prob column; record_decision_log
  already accepts the param. Do NOT add migration 32 or the param again.
- strategy/ml_calibration.py: TODO block already removed in commit abc1234.
```

To generate this context: `git log --oneline -5 -- <owned_files>` before dispatch.
If any owned file has commits since the worktree base, add the context block.

**cwd hygiene during merge:**
After ANY command that runs in a worktree directory, the shell cwd may silently shift.
ALWAYS prefix subsequent commands with `cd /path/to/main/tree &&` to avoid running
git commands in the wrong worktree. This is especially dangerous during Step E when
running `git diff` or `git status` — you may see the worktree's state instead of main's.

**Rate limits:** For 8+ parallel agents, stagger launches with 2-3s delays. If project uses SQLite or local DB, ensure worktree hooks redirect the DB path to an isolated copy (see `worktree-db-redirect.js`).

---

## Orchestrator Step D½ — MONITOR + REBALANCE (optional)

**When to activate:** 6+ agents dispatched, or batch expected to take >5 minutes,
or claims MCP tools are available.

This step runs WHILE agents are working. It does NOT block agent execution.

**Without MCP (lightweight):**
- Track which agents have returned vs. still running
- If an agent returns `status: blocked`, note it for Step E
- If an agent returns much faster than others, it's idle — note for future batch sizing

**With claims MCP (`mcp__claude-flow__claims_*`):**
```
Per agent at dispatch time:
  claims_claim(issueId=task_id, agentId=agent_name, agentType=agent_type)

When agent returns early (fast completion):
  claims_release(issueId=task_id, reason="completed")
  claims_stealable() → check if overloaded agents have stealable work
  claims_steal(issueId=stealable_task, thiefId=idle_agent) → re-dispatch

When agent is stuck (>2x median elapsed time):
  claims_mark-stealable(issueId=task_id, reason="stale")
  → Another idle agent can pick it up

Periodic rebalance check:
  claims_load() → agent utilization metrics
  claims_rebalance(targetUtilization=0.7, dryRun=true) → preview
  If skew >30%: apply rebalance (with user confirmation for >3 agents)
```

**With progress tracking (`mcp__claude-flow__progress_*`):**
```
progress_check() → current completion percentage across all batches
progress_summary() → human-readable status for user
```

---

## Agent Lifecycle (Steps 1-6)

Each agent receives a 6-step template (Analyze → Plan → Red Team → Implement → Test → Report)
embedded in its dispatch prompt. Full template with placeholders and YAML report schema:
see `references/agent-prompt.md`. Orchestrator loads this at dispatch time and fills in
per-task fields (`{task_description}`, `{file_list}`, `{read_only_list}`, etc.).

## Orchestrator Step E — MERGE / VALIDATE

After all agents in a batch return:

**Check for red team conflicts first:**
- Any agent reported `RED_TEAM_CONFLICT`? → Show to user, ask before merging
- Any agent `status: blocked`? → Note it, don't merge, keep task open
- Any agent `status: failed`? → Check if failure is isolated or systemic

### Git Mode

**WORKTREE BASE DRIFT CHECK (mandatory):**
Worktree branches are often created from an older ancestor, NOT from current HEAD —
even after Step 0 commit. Agent edits are uncommitted modifications on a stale base.

```bash
# Check EVERY worktree's HEAD before attempting merge
cd <worktree> && git log --oneline -1
```

If worktree HEAD != main HEAD (common case), use **3-way patch protocol**:

1. Create rollback tag: `git tag pre-parallel-merge-${DISPATCH_BASE_SHA:0:8}-$(date +%s)`
   (If rollback needed: `git reset --hard $DISPATCH_BASE_SHA`)
2. Per worktree: generate diffs for OWNED FILES ONLY (exclude files already modified on main):
   `cd <worktree> && git diff -- <owned_files> > /tmp/<agent>.patch`
3. Apply each patch to main tree with 3-way merge:
   `cd <main_tree> && git apply --3way /tmp/<agent>.patch`
4. Resolve conflicts: "ours" = main's newer code, "theirs" = agent's changes. Typically keep both.
5. Watch for scope mismatches: agent may reference variables/functions from old code that
   were refactored on main. Test suite catches these (NameError, wrong tuple destructuring).

**NEVER use these when worktree HEAD != main HEAD:**
- `git merge` on worktree branch (shows "already up to date" — edits are uncommitted)
- `cp` from worktree to main (overwrites recent main-branch changes)

If worktree HEAD == main HEAD (rare), standard merge works:
1. Create rollback tag
2. Order branches by independence (zero-overlap first)
3. Per branch: ownership check → overlap check → `git merge --no-ff`
4. Conflicts: show to user, let them decide

### Config Mode
1. **Verify backups exist** (created pre-dispatch: `cp -p {file} /tmp/parallel-config-backup-{ts}/`)
2. **Ownership check**: compare files agents actually modified against their ownership list
3. **Validate by type:**
   - `.json` → `python -c "import json; json.load(open('f'))"`
   - `.yaml`/`.yml` → `python -c "import yaml; yaml.safe_load(open('f'))"`
   - `.md` with frontmatter → verify `---` delimiters + required fields
4. **Cross-ref check**: verify links/references between files are consistent
5. **If invalid**: show error, offer per-file selective restore from backup
6. **If all valid**: delete backup dir

### Saga Compensation (rollback protocol for multi-agent failures)

When a merge causes cascading failures (agent A's changes break agent B's):

1. **Identify the failing agent** via test suite errors + `git blame` on failing lines
2. **Selective rollback**: revert ONLY that agent's patch:
   `git apply --reverse /tmp/<failing_agent>.patch`
3. **Re-run tests** to confirm the remaining merges are clean
4. **Mark the failed task** as `status: failed` with reason
5. **If 2+ agents fail**: offer full rollback to `DISPATCH_BASE_SHA` tag
6. **Never leave main in a broken state** — either fix or rollback before proceeding

### Hypothesis-Driven Failure Analysis (for non-obvious test failures)

When G1 test suite fails and the cause isn't immediately clear:

1. Generate 2-3 hypotheses for the failure (e.g., "scope mismatch from agent A",
   "missing import from agent B's refactor", "pre-existing flaky test")
2. For each hypothesis, dispatch a debug agent:
   ```
   Agent(
     description="Debug hypothesis: {hypothesis}",
     subagent_type="team-debugger",
     model="sonnet",
     prompt="Investigate: {hypothesis}. Check {specific files}. Report evidence with file:line citations and confidence (high/medium/low).",
     run_in_background=true
   )
   ```
3. Compare evidence across hypotheses — highest-confidence wins
4. Apply targeted fix based on winning hypothesis

Only use for genuinely ambiguous failures. Most failures are obvious from the stack trace.

**BATCH GATE (mandatory between batches):**
1. All agents in current batch returned? If not, STOP.
2. All `red_team.conflicts` resolved with user? If not, ask.
3. All merges completed without conflict? If not, resolve.
4. **Completeness check passed** (see below)? If not, implement missing items or re-dispatch.
5. **Ownership check passed** (see below)? If not, revert unauthorized files.
6. Full test suite passes? If not, fix or rollback.
7. **Sync for next batch** (if batch N+1 uses worktrees): commit + push batch N's
   merges + inline edits, re-run Step 0 viability. See **Serial-Before-Parallel Invariant**.
8. **Re-run Worktree Necessity Check** if batch N added new tasks (from
   `suggested_follow_ups`) or reshuffled file ownership. The execution mode may shift
   for batch N+1 (e.g., newly-added task creates overlap → switch to `worktree-parallel`).
9. Update DISPATCH_BASE_SHA to post-push HEAD.

Only then: dispatch next batch.

### Pre-commit Verification (mandatory)

Agent self-reports are unreliable. Two grep-based checks before committing:

**Completeness check** — agents silently skip sub-tasks from multi-item prompts.
Extract a greppable token from each concrete plan item, grep for it:

| Plan item | Greppable token |
|-----------|----------------|
| New event/function | exact string, e.g. `"candidate_decision"` |
| Bug fix `X → Y` | `Y` must exist **and** `X` must not |
| New import | full import line |
| New config field | field name |

Zero matches = silently dropped. Implement directly (fastest) or re-dispatch a
narrow agent with an explicit "ONLY implement these missing items" prompt.

**Ownership check** — agents modify files beyond their declared ownership:

```bash
EXPECTED="fileA.py fileB.py strategy/fileC.py"
git diff --stat --name-only | while read f; do
    case " $EXPECTED " in *" $f "*) ;; *) echo "UNAUTHORIZED: $f" ;; esac
done
```

Unauthorized files → `git checkout` to revert (common case), or show diff to user.
Observed failure modes: scope creep refactors, new test files for unowned modules,
opportunistic "fixes" to pre-existing issues, schema-dependent code that breaks
tests elsewhere.

## Orchestrator Step F — BOOKKEEP + LEARN

Update the **original task list file** using agent reports:

**F1. Task statuses:**
- `status: completed` → update using file's existing format (`- [ ]`/`- [x]`, status field, or section headers)
- `status: failed` → add `(FAILED: reason)`, keep open
- `status: blocked` → keep as-is, add note
- `status: conflict` → add `(NEEDS REVIEW: conflict description)`, keep open

**F2. Test matrix** (if the file has one):
- Add `new_tests_added` entries from each agent's report
- Note coverage changes

**F3. New findings:**
- Add `suggested_follow_ups` as new tasks in the file
- Add `hidden_dependencies_found` as annotations on existing tasks
- Record `corrections_made` (task descriptions that were wrong)

**F4. Closed issues update:**
- For each task with `status: completed`, search for a closed issues file (glob: `docs/closed-issues.md`, `CLOSED.md`)
- If found: append completed tasks to its summary table, matching existing format
- If the task was tracked in an open issues file (`open-issues.md`), remove or mark it there too
- If no closed issues file exists, skip (don't create one)

**F5. Dispatch metadata:**
```markdown
## Last Dispatch — {date}
- Completed: {N}/{total}
- Tests: {pass}/{total} ({new_tests} new)
- Models: {sonnet: N, opus: N}
- Conflicts: {list or "none"}
- Follow-ups added: {N}
```

**F6. Learning loop (if MCP intelligence tools available):**
```
Per completed task:
  hooks_intelligence_trajectory-step(action="dispatch", quality=0.0-1.0 based on outcome)

Per batch:
  hooks_model-outcome(task=task_summary, model=model_used, result=success|failure|escalated)
  → Feeds future model routing decisions

If session ending:
  hooks_intelligence_trajectory-end(summary=dispatch_metadata)
```

This is fire-and-forget — never block dispatch on learning.

## Orchestrator Step G — COMMIT + PUSH

**G1. Run full test suite** (cross-agent integration check):
```bash
.polybotenv/bin/python -m pytest --timeout=30   # or project equivalent
```

**Agent test results are advisory, not authoritative.** Worktree agents often cannot
run the full test suite (sandbox permissions, missing DB, old schema). The orchestrator's
G1 test run is the only reliable integration check. If an agent reports "tests: blocked",
this is expected — proceed to G1 regardless.

**G2. If new failures:** identify which agent's changes likely caused it → offer:
  - **Fix agent**: dispatch a targeted fix agent for the specific failure
  - **Selective rollback**: revert just that agent's patch (saga compensation)
  - **Full rollback**: revert to `DISPATCH_BASE_SHA` tag
  - **Hypothesis debug**: if cause unclear, use hypothesis-driven analysis (see Step E)

**G3. Stage + review:**
- All agent-modified files + updated task file + new test files
- `git diff --stat` — verify only expected files, no secrets

**G4. Pre-commit formatter handling:**
If the project has auto-formatters (ruff-format, black, prettier, biome) in pre-commit
hooks, the first commit attempt will likely FAIL because the formatter modifies files.
This is normal. After the formatter runs:
```bash
git add -u && git commit -m "..."   # re-stage formatted files and retry
```
Do NOT use `--no-verify` to bypass. Let the formatter do its job.

**G5. Commit:**
```bash
git commit -m "$(cat <<'EOF'
feat: parallel dispatch — {summary}

Tasks completed:
{per-task one-liner from agent reports}

Tests: {pass}/{total} ({new} new)
Models: {sonnet: N, opus: N}
Mode: {Git|Config}

Co-Authored-By: {current_model} <noreply@anthropic.com>
EOF
)"
```

**G6. Push** only if user has approved. Otherwise: "Changes committed. Run `git push` when ready."

**G7. Session persistence (if enabled):**
```
mcp__claude-flow__session_save(
  sessionId=dispatch_session_id,
  summary="Dispatch complete: N/M tasks, batch K of L"
)
```
This allows resuming an interrupted multi-batch dispatch in a future conversation.

---

## Quick Reference

Flow: 0 → A → B → C → C½ → D → D½ → E → F → G (orchestrator) + 1-6 per agent.
User gates: Step 0 (commit/push), C (plan), C½ (mode), G (push).

## Agent Type Routing

Auto-select based on task content and risk tier:

| Task contains | Agent type | Default Model |
|--------------|-----------|---------------|
| "test", "coverage", "spec" | `tdd-guide` | sonnet |
| "security", "auth", "credential" | `security-reviewer` | sonnet |
| "refactor", "clean", "dead code" | `refactor-cleaner` | sonnet |
| "performance", "optimize", "benchmark" | `performance-optimizer` | sonnet |
| Trading/financial logic | `check-trading` first | sonnet |
| "docs", "readme", "comment" | `doc-updater` | sonnet |
| "schema", "migration", "query", "SQL" | `database-reviewer` | sonnet |
| "investigate", "audit", "analyze", "measure" | `Explore` (read-only) | sonnet |
| "debug", "fix", "broken", "failing" | `team-debugger` | sonnet |
| Multiple categories match | Priority: trading > security > tdd > general | highest-risk model |
| Everything else | `general-purpose` | sonnet |

## When NOT to Use This Skill

- Single task — just implement it directly
- Tasks have circular dependencies that can't be broken
- Tasks require real-time coordination (chat, shared state)
- Fewer than 2 tasks — overhead exceeds benefit
- (Note: all tasks touching the same file is fine — `serial-batches` mode handles it)

## Common Mistakes

Learned patterns from past dispatches. Full table (27 entries): see `references/common-mistakes.md`.

**Top 5 reminders:**
- Orchestrator NEVER implements — agents do
- NEVER auto-push; ask user first
- NEVER `cp` from worktree to main — use 3-way patch protocol
- Agents drop sub-tasks silently — grep for each planned item before committing
- Default to sonnet; reserve opus for critical architecture/security review

## MCP Integration Reference

Optional MCP tools that enhance dispatch when available. The skill works without them.
Full table with trigger conditions: see `references/mcp-integration.md`.

Capabilities: claims/work-stealing, progress tracking, session persistence, shared memory,
model routing feedback, learning trajectories, diff risk analysis, consensus, topology.

## Integration

- **parallel-feature-development** — file ownership strategies, interface contracts, slice patterns
- **parallel-worktree-tasks** — simpler variant without dependencies; config mode backup protocol
- **dispatching-parallel-agents** — independence verification, when NOT to parallelize
- **using-git-worktrees** — worktree directory selection, project setup auto-detection
- **polybot-workflow** — model routing, rate limit policy, dispatch rules
- **verification-before-completion** — final quality gate before claiming done
- **team-composition-patterns** — preset team configurations for common scenarios
- **task-coordination-strategies** — decomposition strategies, workload rebalancing
- **agentic-engineering** — eval-first loops, 15-minute unit rule, cost discipline
- **continuous-agent-loop** — persistent loops for long-running multi-batch dispatches
- **swarm-orchestration** — topology selection (mesh/hierarchical/adaptive)

**Invoked via:** `/parallel-task-dispatch {task-list-file}` or `--dry-run` or `--preset={name}`
