---
name: parallel-task-dispatch
description: Use when you have a task list file with 2+ tasks to implement in parallel. Each agent runs a full 6-step lifecycle (analyze issue, red-team plan, implement, test, report bookkeeping, report for commit). Orchestrator handles dependency graphs, file ownership, model routing, merge/reconcile, task file updates, and commit+push. Supports claims-based work stealing, team presets, eval-first gates, risk scoring, session persistence, and saga rollback. Auto-detects git worktree vs config mode. Triggers on "run tasks in parallel", "dispatch task list", "work through issues list". Not for single tasks.
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
A. Parse task file + risk score      2. Red team — challenge own plan,
B. Build dependency graph               verify files exist, check
C. Assign file ownership + model        assumptions before coding
D. Dispatch parallel batches    →    3. Implement — write code/config
D½. Monitor + rebalance        ↔     4. Test — eval-first gates
E. Merge/validate results     ←     5. Report — structured output
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

**Steps 1-5 are per-agent.** Each agent runs the full lifecycle autonomously in its worktree/context. The orchestrator never implements — it coordinates.

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
| **Core** | 0-G + Agent 1-5 | Claude Code Task tool | Always on |
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

### Preset Details

**Feature team:**
- Lead (sonnet): orchestrates, owns interface contracts + shared types
- Implementers (sonnet): one per vertical slice, worktree-isolated
- Test agent (sonnet): writes tests for interfaces between slices

**Review team:**
- Each reviewer (sonnet) gets one dimension: security, performance, architecture, correctness, trading-safety
- All run in parallel, no worktree needed (read-only)
- Reports merged into unified review with severity ratings

**Debug team (ACH — Analysis of Competing Hypotheses):**
- Each debugger (sonnet) investigates one hypothesis
- Evidence is confidence-weighted: high >80%, medium 50-80%, low <50%
- All cite file:line; orchestrator arbitrates based on evidence weight

**Research team:**
- All Explore agents (sonnet)
- No file ownership — all read-only, no worktree
- Results synthesized by orchestrator

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

**Skip when:** read-only/research agents, config mode, or `WORKTREE_VIABLE=false`.

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

## Orchestrator Step D — DISPATCH

**All agents in a batch dispatched in ONE message.** Each agent receives the full 6-step lifecycle in its prompt.

### Git Mode (worktree viable)

Only use `isolation: "worktree"` when `WORKTREE_VIABLE=true` (see Step 0 viability check):
```
Agent(
  description="Task N: {summary}",
  prompt=AGENT_LIFECYCLE_PROMPT,
  isolation="worktree",
  model="{risk-based model from Step C}",
  run_in_background=true
)
```

### Git Mode (worktree NOT viable — feature branch)

When `WORKTREE_VIABLE=false`, agents implement directly on the current branch without
isolation. File ownership is enforced by instruction only (no physical isolation):
```
Agent(
  description="Task N: {summary}",
  prompt=AGENT_LIFECYCLE_PROMPT,
  model="{risk-based model from Step C}",
  run_in_background=true
)
```
**Without worktree isolation, file overlap is dangerous.** Agents with overlapping owned
files MUST run sequentially (split into separate batches). Agents with non-overlapping
files can still run in parallel.

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

**Recovery from base drift (implement-direct fallback):**
If worktree agents fail due to base drift, do NOT re-dispatch with worktrees.
Instead, use the agent's PLAN output as instructions and implement directly on
the current branch. The agent's analysis (Step 1-2) and plan are still valuable
even when implementation (Step 3) failed.

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

## Agent Lifecycle (Steps 1-5) — embedded in prompt

Each agent receives this as its full instruction set:

```markdown
You are implementing a task{" in an isolated git worktree" | ""}. Follow
these 5 steps IN ORDER. Do not skip any step.

═══════════════════════════════════════════════════════════════
STEP 1 — ANALYZE
═══════════════════════════════════════════════════════════════

Read and fully understand your issue before writing any code.

**Task**: {task_description}

**Depends on**: {dependency_list_or_none}
**Blocks**: {blocks_list_or_none}

Do the following:
- Read all files referenced in the task description
- If the task has "Depends on" items, verify each dependency:
  - File dependency: Glob/Read to confirm path exists
  - Function/class dependency: Grep for name in target file
  - Schema dependency: Read migration or schema file for table/column
  - If ANY dependency is missing → set status: blocked, report which
- Do NOT guess or work around missing dependencies
- Identify exactly which functions, classes, or sections need changing
- Note the current state: what exists now vs what the task asks for

═══════════════════════════════════════════════════════════════
STEP 2 — RED TEAM YOUR PLAN
═══════════════════════════════════════════════════════════════

Before writing code, challenge your own plan:

- [ ] Do the files mentioned in the task actually exist? At the paths
      described? With the functions/classes referenced?
- [ ] Is the problem description still accurate? (Code may have changed
      since the issue was written)
- [ ] Will your planned changes break anything outside your owned files?
- [ ] Are there hidden dependencies — other code that imports/calls
      what you're changing?
- [ ] Does your approach match the project's patterns? (Check nearby
      files for conventions)
- [ ] Could this change cause a regression in existing tests? (Grep
      for test files that import your target modules)

If you find a factual error in the task (file renamed, function deleted,
problem already fixed), report it in your output — do NOT silently
reinterpret the task.

If you cannot reconcile a conflict between the task description and
reality, record it in your Step 5 report under `red_team.conflicts`.
The orchestrator will ask the user before merging.

═══════════════════════════════════════════════════════════════
STEP 3 — IMPLEMENT
═══════════════════════════════════════════════════════════════

**Owned Files** (you may modify ONLY these):
{file_list}

**Read-Only Files** (reference only, do NOT modify):
{read_only_list}

Constraints:
- Modify ONLY files in your owned list
- Do NOT create files outside owned directories (owned path `src/foo/`
  includes its subdirectories; test fixtures go in the project's test dir)
- Follow existing code patterns and conventions
- If you need changes to a read-only file, describe what you need
  in your report (the orchestrator will coordinate)

═══════════════════════════════════════════════════════════════
STEP 4 — TEST (eval-first gate)
═══════════════════════════════════════════════════════════════

**4a. Baseline snapshot (BEFORE your changes — run first):**
Run tests relevant to your changes and record pass/fail counts.
This establishes what was already broken vs what you broke.

Auto-detect test command if no hint given:
- `.polybotenv/` or `pytest.ini` → `.polybotenv/bin/python -m pytest --timeout=30`
- `package.json` → `npm test`
- `Cargo.toml` → `cargo test`
- `go.mod` → `go test ./...`
- None found → report `tests.command: "none detected"`

**4b. Post-implementation tests (AFTER your changes):**
- Run the same test command again
- Compare: new failures = your regressions; pre-existing failures = not yours
- If your changes add new functionality, write tests for it
- If tests fail that are unrelated to your changes, note them as
  pre-existing — do NOT fix unrelated tests

**4c. Eval gate:**
- If new regressions > 0: attempt to fix. If fix fails, set
  `status: failed` with regression details. Do NOT submit broken code.
- If all new tests pass + no new regressions: proceed to Step 5

═══════════════════════════════════════════════════════════════
STEP 5 — REPORT
═══════════════════════════════════════════════════════════════

Return a structured report. The orchestrator uses this for merge,
bookkeeping, and commit. Be precise.

```yaml
task_id: {N}
task_summary: "{one_line}"
status: {completed | failed | blocked | conflict}
risk_tier: {critical | high | standard | low | research}
model_used: "{sonnet | opus}"
worktree_branch: "{branch name or null}"
elapsed_minutes: {N}

# Step 1 findings
analysis:
  dependencies_verified: {true | false | "missing: X"}
  files_examined: [list]

# Step 2 findings
red_team:
  all_facts_verified: {true | false}
  conflicts: ["RED_TEAM_CONFLICT: ..." or empty]
  corrections_made: ["description" or empty]
  hidden_dependencies_found: ["description" or empty]
  regression_risk: {none | low | medium | high}

# Step 3 results
implementation:
  files_modified: ["path (+lines/-lines)" list]
  files_created: ["path" list or empty]
  files_read: ["path" list]
  approach: "{brief description}"

# Step 4 results (eval-first gate)
tests:
  command: "{what you ran}"
  baseline: {passed: N, failed: N}       # BEFORE changes
  result: {passed: N, failed: N}         # AFTER changes
  new_regressions: {N}                   # result.failed - baseline.failed
  skipped: {N}
  new_tests_added: ["test_name: what it covers" list or empty]
  pre_existing_failures: ["test_name" list or empty]

# For orchestrator bookkeeping
bookkeeping:
  suggested_follow_ups: ["new task description" list or empty]
  cross_task_needs:
    - {task_id: N, need: "what", blocking: true|false}
  task_file_notes: "{anything to record on this issue}"
```
```

---

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
8. Update DISPATCH_BASE_SHA to post-push HEAD.

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

| Layer | Step | What | Gate |
|-------|------|------|------|
| **Orchestrator** | 0 | Clean tree, commit + push, resume | User approves commit/push |
| **Orchestrator** | A | Parse + risk score | — |
| **Orchestrator** | B | Dependency graph + critical path | — |
| **Orchestrator** | C | File ownership + model routing | User approves plan |
| **Agent** | 1 | Analyze issue, check depends/blocks | Abort if dependency missing |
| **Agent** | 2 | Red team own plan | Report conflicts to orchestrator |
| **Agent** | 3 | Implement within owned files | — |
| **Agent** | 4 | Eval-first test gate (before + after) | Abort if new regressions |
| **Agent** | 5 | Structured YAML report | — |
| **Orchestrator** | D½ | Monitor + rebalance (optional) | — |
| **Orchestrator** | E | Merge/validate, saga compensation | User resolves conflicts |
| **Orchestrator** | F | Bookkeep + learning loop | — |
| **Orchestrator** | G | Full test suite, commit, push, persist | User approves push |

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
- All tasks modify the same file — sequential, not parallel
- Tasks have circular dependencies that can't be broken
- Tasks require real-time coordination (chat, shared state)
- Fewer than 2 tasks — overhead exceeds benefit

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Orchestrator implements code | Orchestrator NEVER implements — agents do |
| Agent skips red team | Steps 1-5 are mandatory, in order |
| Agent fixes unrelated tests | Report pre-existing failures, don't fix |
| Agent silently reinterprets task | Report RED_TEAM_CONFLICT, let user decide |
| Dispatching Batch 2 before merging Batch 1 | Sequential — merge then dispatch |
| Committing without full test suite | Step G1 catches cross-agent integration issues |
| Pushing without approval | NEVER auto-push |
| Serial work unpushed before a worktree dispatch | Commit + push to `origin/<default>` first, re-verify viability. Applies to initial state, between-batch merges, AND inline orchestrator fixes. See **Serial-Before-Parallel Invariant**. |
| Agent blocks on empty test hint | Auto-detect test command; report "none detected" if unavailable |
| Merging before all batch agents finish | BATCH GATE — all 5 checks must pass before next batch |
| Config mode with no backup | Always create `/tmp` backup before config dispatch |
| `cp` from worktree to main tree | NEVER `cp` — worktree is on old base, overwrites recent changes. Use 3-way patch. |
| `git merge` on worktree branch | Agents don't commit — edits are uncommitted. Merge shows "up to date". Use patch. |
| Running git commands after worktree `cd` | cwd silently drifts to worktree dir. ALWAYS prefix with `cd <main_tree> &&`. |
| Agent re-adds migration/changes already on main | Include `ALREADY ON MAIN` block in agent prompt listing recent changes to owned files. |
| NameError after patch apply (scope mismatch) | Agent coded against old call chain. Full test suite catches it. Fix manually — thread var through new intermediary. |
| Two agents write same migration number | Assign migration numbers in Step C based on current schema version + task order. Tell each agent its number. |
| Using opus when sonnet suffices | Default to sonnet for all agents. Reserve opus for complex architecture + security-critical review. |
| Leaving main broken after partial merge | Use saga compensation — selective rollback of failing agent's patch. Never leave broken state. |
| Using worktrees on feature branches | Worktrees create from DEFAULT branch, not current branch. Run viability check in Step 0. If not viable, OFFER MERGE-FORWARD (ff-merge to main + push) as the recommended fix before falling back to no-isolation. |
| Falling back to no-isolation when merge-forward was available | Merge-forward restores true parallel isolation — ask the user FIRST before degrading to sequential-for-overlaps mode. |
| Worktree agent "only planned, didn't implement" | Base drift — agent landed on old code. Use agent's plan as instructions, implement directly on current branch. Do NOT re-dispatch with worktrees. |
| Not recording dispatch outcomes | F6 learning loop improves future model routing and agent selection. |
| Trusting agent's "complete" report | Agents drop sub-tasks silently. Grep for each planned item before committing — see Pre-commit Verification in Step E. |
| Skipping `git diff --stat` before commit | Agents modify files outside their ownership. Run the ownership check and revert unauthorized files. |
| Multi-item agent prompt as prose paragraph | Items buried in prose get skipped. Number each sub-task; require per-item status in the Step 5 report. |
| No-worktree agent runs full test suite | Concurrent edits produce false regressions. No-worktree agents skip the full suite; orchestrator runs it at G1. |

## MCP Integration Reference

Optional MCP tools that enhance dispatch when available. The skill works without them —
they add coordination, persistence, and learning capabilities.

| Capability | Tools | When |
|-----------|-------|------|
| **Claims / work stealing** | `claims_claim`, `claims_release`, `claims_steal`, `claims_rebalance`, `claims_load` | 6+ agents, uneven task sizes |
| **Progress tracking** | `progress_check`, `progress_summary` | 3+ batches, user wants visibility |
| **Session persistence** | `session_save`, `session_restore` | Multi-hour dispatches, resumable work |
| **Shared memory** | `hive-mind_init`, `hive-mind_memory`, `hive-mind_broadcast` | Cross-agent state (shared config, feature flags) |
| **Model routing feedback** | `hooks_model-route`, `hooks_model-outcome`, `hooks_model-stats` | Continuous model selection improvement |
| **Learning trajectories** | `hooks_intelligence_trajectory-start/step/end` | Pattern extraction for future dispatches |
| **Diff risk analysis** | `analyze_diff`, `analyze_diff-risk`, `analyze_diff-reviewers` | Auto-reviewer suggestion post-merge |
| **Consensus** | `coordination_consensus`, `hive-mind_consensus` | Multi-agent decisions (rare — e.g., conflicting approaches) |
| **Topology** | `coordination_topology`, `swarm_init` | 10+ agents, complex dependency graphs |

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
