---
name: parallel-task-dispatch
description: Use when you have a task list file with 2+ tasks to implement in parallel. Each agent runs a full 6-step lifecycle (analyze issue, red-team plan, implement, test, report bookkeeping, report for commit). Orchestrator handles dependency graphs, file ownership, merge/reconcile, task file updates, and commit+push. Auto-detects git worktree vs config mode. Triggers on "run tasks in parallel", "dispatch task list", "work through issues list". Not for single tasks.
---

# Parallel Task Dispatch

## Architecture

Two layers — **orchestrator** (you) and **agents** (dispatched subagents):

```
ORCHESTRATOR (shared state)          AGENTS (per-task, isolated)
================================     ================================
0. Pre-flight — clean tree,          1. Analyze — read issue, check
   commit + push                        depends/blocks, verify facts
A. Parse task file                   2. Red team — challenge own plan,
B. Build dependency graph               verify files exist, check
C. Assign file ownership                assumptions before coding
D. Dispatch parallel batches    →    3. Implement — write code/config
E. Merge/validate results     ←     4. Test — run relevant tests
F. Bookkeep task file                5. Report — structured output
G. Commit + push                        for orchestrator steps E-G
```

**Steps 1-5 are per-agent.** Each agent runs the full lifecycle autonomously in its worktree/context. The orchestrator never implements — it coordinates.

Two execution modes — auto-detected:

| Mode | When | Isolation | Rollback |
|------|------|-----------|----------|
| **Git** | Target files in a git repo | `isolation: "worktree"` | `git tag` + `git reset` |
| **Config** | Files outside git (`~/.claude/`) | File ownership only | Timestamped backups |

---

## Orchestrator Step 0 — PRE-FLIGHT (clean tree + push)

**Why:** Worktrees are created from the committed branch state. Uncommitted changes are invisible to agents and will cause merge conflicts when their work comes back. This step ensures every agent starts from the same clean baseline.

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
- Config mode (files outside git) skips this step entirely

**After clean state confirmed**, record the baseline:
```bash
git rev-parse HEAD   # save as DISPATCH_BASE_SHA for rollback reference
```

## Orchestrator Step A — PARSE

Read the task list file. Extract per task:

| Field | Look for | Effect |
|-------|---------|--------|
| Depends on | `depends on: #N`, `after: #N`, `requires: #N` (first match wins) | Cannot start until dependency completes |
| Blocks | `blocks: #N`, `before: #N` | Dependents wait |
| Priority | `P0/P1/P2`, `priority: high/med/low` | Order within batch |
| Status | `[x]`, `DONE`, `CLOSED` | Skip |

## Orchestrator Step B — DEPENDENCY GRAPH

- Topological sort tasks into parallel batches
- Batch 1: no dependencies (run in parallel)
- Batch 2: depends on Batch 1 results (run after Batch 1 merges)
- Circular dependencies: if topological sort fails, show cycle to user ("Tasks #A -> #B -> #C -> #A"), ask which edge to remove, re-sort, verify. If user declines, abort.

## Orchestrator Step C — FILE OWNERSHIP

Per task, identify target files (from description or grep/glob). Build ownership matrix — one owner per file. Present execution plan:

```
EXECUTION PLAN
==============
Batch 1 (parallel): #1, #3
Batch 2 (after #1):  #2 (depends on #1)

| # | Task | Batch | Owned Files | Read-Only |
|---|------|-------|-------------|-----------|
```

**Overlap detection:** If a file appears in 2+ tasks within the same batch, assign to higher-priority task; other gets read-only. If both MUST write, split into sequential batches.

**Migration number coordination:** If multiple tasks add database migrations, pre-assign
migration numbers in the execution plan based on the current schema version. Tell each
agent its assigned number explicitly (e.g., "You are adding migration 33. Do NOT use any
other number."). Check current version: `grep -c '_migrate_' storage.py` or equivalent.

**Research-only agents:** Tasks that only need code reading (audits, investigations,
data queries) should be dispatched WITHOUT `isolation: "worktree"`. This avoids base
drift entirely and runs faster. Only use worktree isolation for agents that modify files.

**User approves before dispatch.**

## Orchestrator Step D — DISPATCH

**All agents in a batch dispatched in ONE message.** Each agent receives the full 6-step lifecycle in its prompt.

### Git Mode

```
Agent(
  description="Task N: {summary}",
  prompt=AGENT_LIFECYCLE_PROMPT,
  isolation="worktree",
  run_in_background=true
)
```

### Config Mode

```
Agent(
  description="Task N: {summary}",
  prompt=AGENT_LIFECYCLE_PROMPT,
  run_in_background=true
)
```

**STOP after dispatch.** Wait for all agents in the batch to return.

**ALREADY-ON-MAIN context (mandatory for worktree agents):**
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

**Rate limits:** For 8+ parallel agents, stagger launches with 2-3s delays. Use `model: "sonnet"` for read-only agents to reduce pressure. If project uses SQLite or local DB, ensure worktree hooks redirect the DB path to an isolated copy (see `worktree-db-redirect.js`).

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
STEP 4 — TEST
═══════════════════════════════════════════════════════════════

Run tests relevant to your changes. Auto-detect if no hint given:
- `.polybotenv/` or `pytest.ini` → `.polybotenv/bin/python -m pytest --timeout=30`
- `package.json` → `npm test`
- `Cargo.toml` → `cargo test`
- `go.mod` → `go test ./...`
- None found → report `tests.command: "none detected"`

- Run tests BEFORE and AFTER your changes to establish a diff
- If your changes add new functionality, write tests for it
- If tests fail that are unrelated to your changes, note them as
  pre-existing — do NOT fix unrelated tests

═══════════════════════════════════════════════════════════════
STEP 5 — REPORT
═══════════════════════════════════════════════════════════════

Return a structured report. The orchestrator uses this for merge,
bookkeeping, and commit. Be precise.

```yaml
task_id: {N}
task_summary: "{one_line}"
status: {completed | failed | blocked | conflict}
worktree_branch: "{branch name or null}"  # optional — orchestrator uses for merge
elapsed_minutes: {N}                       # optional — detect hung agents

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

# Step 3 results
implementation:
  files_modified: ["path (+lines/-lines)" list]
  files_created: ["path" list or empty]
  files_read: ["path" list]              # optional — detect reads outside ownership
  approach: "{brief description}"

# Step 4 results
tests:
  command: "{what you ran}"
  passed: {N}
  failed: {N}
  skipped: {N}
  new_tests_added: ["test_name: what it covers" list or empty]
  pre_existing_failures: ["test_name" list or empty]

# For orchestrator bookkeeping
bookkeeping:
  suggested_follow_ups: ["new task description" list or empty]
  cross_task_needs:                      # structured, not prose
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

**BATCH GATE (mandatory between batches):**
1. All agents in current batch returned? If not, STOP.
2. All `red_team.conflicts` resolved with user? If not, ask.
3. All merges completed without conflict? If not, resolve.
4. Full test suite passes? If not, fix or rollback.
5. Update DISPATCH_BASE_SHA to post-merge HEAD.

Only then: dispatch next batch.

## Orchestrator Step F — BOOKKEEP

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

**F5. Closed issues update:**
- For each task with `status: completed`, search for a closed issues file (glob: `docs/closed-issues.md`, `CLOSED.md`)
- If found: append completed tasks to its summary table, matching existing format
- If the task was tracked in an open issues file (`open-issues.md`), remove or mark it there too
- If no closed issues file exists, skip (don't create one)

**F6. Dispatch metadata:**
```markdown
## Last Dispatch — {date}
- Completed: {N}/{total}
- Tests: {pass}/{total} ({new_tests} new)
- Conflicts: {list or "none"}
- Follow-ups added: {N}
```

## Orchestrator Step G — COMMIT + PUSH

**G1. Run full test suite** (cross-agent integration check):
```bash
.polybotenv/bin/python -m pytest --timeout=30   # or project equivalent
```

**Agent test results are advisory, not authoritative.** Worktree agents often cannot
run the full test suite (sandbox permissions, missing DB, old schema). The orchestrator's
G1 test run is the only reliable integration check. If an agent reports "tests: blocked",
this is expected — proceed to G1 regardless.

**G2. If new failures:** identify which agent's changes likely caused it → offer fix agent, rollback that merge, or rollback all.

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
Mode: {Git|Config}

Co-Authored-By: {current_model} <noreply@anthropic.com>
EOF
)"
```

**G5. Push** only if user has approved. Otherwise: "Changes committed. Run `git push` when ready."

---

## Quick Reference

| Layer | Step | What | Gate |
|-------|------|------|------|
| **Orchestrator** | 0 | Clean tree, commit + push | User approves commit/push |
| **Orchestrator** | A-C | Parse, deps, ownership | User approves plan |
| **Agent** | 1 | Analyze issue, check depends/blocks | Abort if dependency missing |
| **Agent** | 2 | Red team own plan | Report conflicts to orchestrator |
| **Agent** | 3 | Implement within owned files | — |
| **Agent** | 4 | Run tests, write new tests | Report pass/fail |
| **Agent** | 5 | Structured YAML report | — |
| **Orchestrator** | E | Merge/validate, handle conflicts | User resolves red team conflicts |
| **Orchestrator** | F | Update task file, record findings | — |
| **Orchestrator** | G | Full test suite, commit, push | User approves push |

## Agent Type Routing

Auto-select based on task content:

| Task contains | Agent type |
|--------------|-----------|
| "test", "coverage", "spec" | `tdd-guide` |
| "security", "auth", "credential" | `security-reviewer` |
| "refactor", "clean", "dead code" | `refactor-cleaner` |
| "performance", "optimize" | `performance-optimizer` |
| Trading/financial logic | `check-trading` first |
| "docs", "readme", "comment" | `doc-updater` |
| "schema", "migration", "query", "SQL" | `database-reviewer` |
| Multiple categories match | Priority: trading > security > tdd > general |
| Everything else | `general-purpose` |

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
| Dispatching with dirty working tree | Step 0 — commit + push first; worktrees won't see uncommitted changes |
| Agent blocks on empty test hint | Auto-detect test command; report "none detected" if unavailable |
| Merging before all batch agents finish | BATCH GATE — all 5 checks must pass before next batch |
| Config mode with no backup | Always create `/tmp` backup before config dispatch |
| `cp` from worktree to main tree | NEVER `cp` — worktree is on old base, overwrites recent changes. Use 3-way patch. |
| `git merge` on worktree branch | Agents don't commit — edits are uncommitted. Merge shows "up to date". Use patch. |
| Running git commands after worktree `cd` | cwd silently drifts to worktree dir. ALWAYS prefix with `cd <main_tree> &&`. |
| Agent re-adds migration/changes already on main | Include `ALREADY ON MAIN` block in agent prompt listing recent changes to owned files. |
| NameError after patch apply (scope mismatch) | Agent coded against old call chain. Full test suite catches it. Fix manually — thread var through new intermediary. |
| Two agents write same migration number | Assign migration numbers in Step C based on current schema version + task order. Tell each agent its number. |

## Integration

- **parallel-feature-development** — file ownership strategies, interface contracts, slice patterns
- **parallel-worktree-tasks** — simpler variant without dependencies; config mode backup protocol
- **dispatching-parallel-agents** — independence verification, when NOT to parallelize
- **using-git-worktrees** — worktree directory selection, project setup auto-detection
- **polybot-workflow** — model routing, rate limit policy, dispatch rules
- **verification-before-completion** — final quality gate before claiming done

**Invoked via:** `/parallel-task-dispatch {task-list-file}` or `--dry-run`
