---
name: parallel-task-dispatch
description: Dispatch 2+ tasks from a file as parallel agents. Full lifecycle (analyze→plan→red-team→implement→test→report) or light (analyze→plan→report). Handles deps, file ownership, risk scoring, batching, merge, and commit. Default mode is file-ownership-parallel; worktrees opt-in via --worktree.
---

# Parallel Task Dispatch

**Source:** https://github.com/kerfern/claude-code-parallel-task-dispatch

## Architecture

```
ORCHESTRATOR              AGENTS (per-task)
0. Pre-flight             1. Analyze  2. Plan
A. Parse + risk score     3. Red team 4. Implement
B. Dependency graph       5. Test     6. Report
C. File ownership
C1/2. Mode check
D. Dispatch  ──────────→  (steps 1-6 or 1-2+6 light)
E. Merge/validate  ←────
F. Bookkeep
G. Commit + push
```

Orchestrator coordinates — agents implement. Light lifecycle (research/docs) skips steps 3-5.

### Execution Modes

| Mode | When | Default |
|------|------|---------|
| `file-ownership-parallel` | Disjoint files | **YES** |
| `serial-batches` | Overlapping files | No |
| `worktree-parallel` | `--worktree` + main branch | No — see `references/worktree-mode.md` |

### Team Presets

`preset: feature` (1 lead + 2-3 impl), `review` (3-5 parallel), `debug` (3 competing), `fullstack`, `migration`, `research` (Explore agents).

---

## Step 0 — PRE-FLIGHT

```bash
git status --short && git log @{u}..HEAD --oneline 2>&1 && git rev-parse HEAD
```

- Uncommitted tracked changes → STOP, ask user to commit
- Unpushed commits → STOP, ask user to push
- Save `DISPATCH_BASE_SHA` for rollback
- NEVER auto-commit or auto-push
- Worktree mode: run viability check from `references/worktree-mode.md`

## Step A — PARSE + RISK

Read task file. Per task extract: depends-on, blocks, priority, status (skip done).

| Risk | Keywords | Model |
|------|----------|-------|
| Critical | auth, payment, trading, credential | sonnet (opus for review) |
| High | migration, schema, delete, refactor | sonnet |
| Standard | feature, bugfix, implementation | sonnet |
| Low | docs, comment, readme, config | sonnet |
| Research | investigate, audit, analyze | sonnet (Explore) |

## Step B — DEPENDENCY GRAPH

Topological sort into batches. Batch 1 = no deps. Batch N = deps on batch N-1. Show critical path.

## Step C — FILE OWNERSHIP

One owner per file. Show plan table to user:

```
| # | Task | Batch | Risk | Model | Type | Owned Files | Read-Only |
```

- Overlap → assign to higher priority; other gets read-only. Both must write → serial batches.
- Migrations → pre-assign numbers.
- Sonnet default. Opus only for critical architecture/security.
- **User approves before dispatch.**

## Step C1/2 — MODE CHECK

Disjoint files → `file-ownership-parallel`. Overlap → `serial-batches`. Show mode + override options.

## Step D — DISPATCH

**CRITICAL — AGENT PROMPT MUST USE LIFECYCLE TEMPLATE:**
Do NOT write custom instruction prompts. Agents given instructions like "Add method X to file Y"
will plan but NOT implement. You MUST embed the full 6-step lifecycle template from
`references/agent-prompt.md` with placeholders filled in. This is the #1 cause of dispatch failure.

All batch agents dispatched in ONE message:

```python
Agent(
  description="Task N: {summary}",
  prompt="""<paste full lifecycle template from references/agent-prompt.md
             with {task_description}, {file_list}, {read_only_list},
             {dependency_list_or_none}, {blocks_list_or_none} filled in>""",
  model="sonnet",           # from Step C risk routing
  run_in_background=True,
  # isolation="worktree",   # ONLY in worktree-parallel mode
)
```

| Agent type | Prompt template |
|-----------|----------------|
| Implementation | **Full** lifecycle (steps 1-6) from `references/agent-prompt.md` |
| Explore, doc-updater, research | **Light** lifecycle (steps 1-2+6) |

**After dispatch: STOP. Wait for all agents.**

**When agent returns:**
1. Only planned, didn't implement → implement directly using agent's plan
2. `status: blocked` → check dependency
3. Modified files outside ownership → caught at Step E

### Agent Type Routing

| Task keywords | Agent type | Lifecycle |
|--------------|-----------|-----------|
| test, coverage | `tdd-guide` | full |
| security, auth | `security-reviewer` | full |
| refactor, clean | `refactor-cleaner` | full |
| performance | `performance-optimizer` | full |
| trading/financial | `check-trading` first | full |
| docs, readme | `doc-updater` | light |
| schema, migration, SQL | `database-reviewer` | full |
| investigate, audit | `Explore` | light |
| debug, fix, broken | `team-debugger` | full |
| default | `general-purpose` | full |

## Step E — MERGE / VALIDATE

1. Check red team conflicts → ask user
2. Check blocked/failed agents
3. **Git mode**: rollback tag, `git diff --stat`, ownership check
4. **Worktree mode**: 3-way patch protocol (see `references/worktree-mode.md`)
5. **Config mode**: verify backups, validate JSON/YAML, cross-ref check

### Batch Gate (mandatory between batches)

1. All agents returned
2. Red team conflicts resolved
3. Merges clean
4. **Completeness check**: grep for each planned item — agents silently drop sub-tasks
5. **Ownership check**: `git diff --name-only` vs expected files; revert unauthorized
6. Full test suite passes
7. Worktree mode: commit + push + re-check viability
8. Update DISPATCH_BASE_SHA

### Completeness Check

Agents drop sub-tasks. For each plan item, grep for a unique token:
- New function → grep function name
- Bug fix X→Y → Y exists AND X doesn't
- New import → grep import line

Zero matches = silently dropped. Implement directly.

### Ownership Check

```bash
git diff --stat --name-only | while read f; do
  case " $EXPECTED " in *" $f "*) ;; *) echo "UNAUTHORIZED: $f" ;; esac
done
```

## Step F — BOOKKEEP

Update task file: completed/failed/blocked statuses, new tests, follow-ups. Add dispatch metadata.

## Step G — COMMIT + PUSH

1. **Full test suite** (cross-agent integration — agent results are advisory only)
2. Failures → fix agent, selective rollback (`references/saga-rollback.md`), or full rollback
3. `git diff --stat` — verify files, no secrets
4. Commit (ask user first). Push (ask user first).

---

## Common Mistakes

See `references/common-mistakes.md`. Top reminders:
- **Agents given custom prompts only plan — use the lifecycle template**
- Orchestrator NEVER implements (except when agent fails to)
- NEVER auto-push
- Agents drop sub-tasks — grep before committing
- Default `file-ownership-parallel`; worktrees opt-in
- Default sonnet; opus for critical review only

## References

| File | Contents |
|------|----------|
| `references/agent-prompt.md` | Full + light lifecycle templates with YAML report |
| `references/common-mistakes.md` | Observed + theoretical failure patterns |
| `references/worktree-mode.md` | Viability, merge-forward, 3-way patch, Serial-Before-Parallel |
| `references/saga-rollback.md` | Selective rollback, hypothesis-driven failure analysis |
| `references/session-persistence.md` | Resume/save for multi-hour dispatches |
| `references/mcp-integration.md` | Optional MCP tools: claims, progress, memory, learning |
