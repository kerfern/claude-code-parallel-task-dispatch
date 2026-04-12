---
name: parallel-task-dispatch
description: Dispatch 2+ tasks as parallel agents. Full lifecycle (analyze→plan→red-team→implement→test→report) or light (analyze→findings→report). Handles deps, file ownership, risk scoring, batching, merge, saga rollback, and commit.
---

# Parallel Task Dispatch

**Source:** https://github.com/kerfern/claude-code-parallel-task-dispatch — `/update-parallel-task-dispatch` to pull latest.

## Architecture

```
ORCHESTRATOR (shared state)          AGENTS (per-task)
================================     ================================
0. Pre-flight — clean tree,          1. Analyze — read issue, check
   commit + push                        depends/blocks, verify facts
A. Parse task file + risk score      2. Plan — files, changes, order
B. Build dependency graph            3. Red team — challenge plan
C. Assign file ownership + model     4. Implement — write code/config
C½. Execution mode check             5. Test — eval-first gates
D. Dispatch parallel batches    →    6. Report — structured YAML
D½. Monitor + rebalance        ↔
E. Merge/validate results      ←    COORDINATION (MCP, optional)
F. Bookkeep task file + learn        See references/mcp-integration.md
G. Commit + push
```

Steps 1-6 per agent (full) or 1-2+6 (light for research/docs). Orchestrator never implements.

## Modes & Capabilities

| Layer | When | Default | Requires |
|-------|------|---------|----------|
| **`file-ownership-parallel`** | Disjoint files | **YES** | — |
| **`serial-batches`** | Overlapping files | No | — |
| **`worktree-parallel`** | `--worktree` + main branch | No | `references/worktree-mode.md` |
| **Config mode** | Files outside git | Auto-detect | — |
| Risk scoring | All tasks | On | Keyword heuristic |
| Model routing | All agents | On | Built into dispatch |
| Eval-first gates | Agent Step 5 | On | Tests before + after |
| Claims & rebalance | 6+ agents | Off | `mcp__claude-flow__claims_*` |
| Progress tracking | 3+ batches | Off | `mcp__claude-flow__progress_*` |
| Session persistence | Multi-hour | Off | `mcp__claude-flow__session_*` |
| Learning loop | Post-dispatch | Off | `mcp__claude-flow__hooks_intelligence_*` |

## Team Presets

| Preset | Agents | When |
|--------|--------|------|
| **feature** | 1 lead + 2-3 impl | Multi-file feature |
| **review** | 3-5 parallel reviewers | Security/perf/arch audit |
| **debug** | 3 parallel debuggers (ACH) | Complex bug, multiple hypotheses |
| **fullstack** | frontend + backend + API + test | Cross-layer feature |
| **migration** | 2 impl + 1 reviewer | Framework upgrade |
| **research** | 3-5 Explore agents | Investigation, audit |

---

## Step 0 — PRE-FLIGHT

- Uncommitted tracked changes → STOP, ask user to commit
- Unpushed commits → STOP, ask user to push
- Save `git rev-parse HEAD` as `DISPATCH_BASE_SHA` for rollback
- NEVER auto-commit or auto-push
- Worktree mode: run viability check from `references/worktree-mode.md`

## Step A — PARSE + RISK SCORE

Read task file. Per task extract: `depends on`, `blocks`, priority (`P0/P1/P2`), status (skip done).

| Risk Tier | Keywords | Model | Review Gate |
|-----------|----------|-------|-------------|
| Critical | auth, payment, trading, credential, secret | sonnet (opus review) | Mandatory security-reviewer |
| High | migration, schema, delete, refactor, breaking | sonnet | Full suite + diff review |
| Standard | feature, bugfix, implementation | sonnet | Standard batch gate |
| Low | docs, comment, readme, config, typo | sonnet | Ownership check only |
| Research | investigate, audit, analyze, benchmark | sonnet (Explore) | Report only — no merge |

## Step B — DEPENDENCY GRAPH

Topological sort into batches. Batch 1 = no deps, Batch N = deps on N-1. Circular deps → show cycle, ask user which edge to remove. Highlight critical path.

## Step C — FILE OWNERSHIP + MODEL

One owner per file. Present plan table to user:

```
| # | Task | Batch | Risk | Model | Agent Type | Owned Files | Read-Only |
```

- Overlap in same batch → assign to higher priority; other gets read-only. Both must write → serial batches.
- Multiple migrations → pre-assign numbers from current schema version.
- Research agents: no worktree isolation, no file ownership.
- Sonnet default. Opus only for critical architecture/security review.
- **User approves before dispatch.**

## Step C½ — EXECUTION MODE CHECK

| File overlap? | Mode |
|---------------|------|
| None (disjoint) | `file-ownership-parallel` (default) |
| Overlap exists | `serial-batches` |

Show mode. User may override to `worktree-parallel` (requires `--worktree` + viable state from Step 0).

## Step D — DISPATCH

All batch agents dispatched in ONE message. Each gets its lifecycle template from `references/agent-prompt.md` with placeholders filled. The template includes a self-enforcing implementation gate and 3-attempt test-iterate loop.

```python
Agent(
  description="Task N: {summary}",
  prompt=FULL_LIFECYCLE_TEMPLATE,      # from references/agent-prompt.md, placeholders filled
  model="sonnet",                      # from Step C risk routing
  run_in_background=True,
  # isolation="worktree",              # ONLY in worktree-parallel mode
)
```

**Fast-path — skip agents when:**
- Read-only tasks (verification, git-log, coverage report) → orchestrator runs directly
- Small scope (≤4 files) with detailed plan → orchestrator implements directly

**After dispatch: STOP. Wait for all agents.**

**When agent returns — implementation gate check:**

| Report says | Action |
|-------------|--------|
| `code_written: false` or no `files_modified` | **Re-dispatch once** with override template (`references/agent-prompt.md`). Skips Steps 1-3, inlines plan, demands code. |
| Override also plan-only | Implement directly using the plan. Max 1 re-dispatch. |
| `status: failed` (test attempts exhausted) | Review failure report + attempt history. Fix directly or defer. |
| `status: blocked` | Check dependency, unblock or defer. |
| `status: completed` | Proceed to Step E. |
| Files outside ownership | Caught at Step E ownership check. |
| Success but Step G suite fails | Rewrite directly — do NOT re-dispatch. |

## Step D½ — MONITOR (optional)

Activate for 6+ agents or >5 min batches. Track returns, note blocked agents. With MCP: see `references/mcp-integration.md`.

## Step E — MERGE / VALIDATE

After all batch agents return:

1. Red team conflicts → show to user, ask before merging
2. Blocked/failed agents → don't merge, keep open
3. **Git mode**: rollback tag, `git diff --stat`, ownership check
4. **Worktree mode**: 3-way patch protocol per `references/worktree-mode.md`
5. **Config mode**: verify backups exist, validate JSON/YAML, cross-ref links

### Batch Gate (mandatory between batches)

1. All agents returned
2. Red team conflicts resolved
3. Merges clean
4. **Completeness**: grep each planned item (function name, import, fix token) — zero matches = silently dropped → implement directly
5. **Ownership**: `git diff --name-only` vs expected — unauthorized → revert
6. **Full test suite** — not agent's slice. Agents call their narrow scope "full suite"
7. Worktree mode: commit + push + re-check viability
8. Re-run C½ if batch added tasks or reshuffled ownership
9. Update DISPATCH_BASE_SHA

For cascading failures: `references/saga-rollback.md`.

## Step F — BOOKKEEP

| Action | Detail |
|--------|--------|
| Task statuses | `completed` → mark done; `failed` → add reason, keep open; `blocked`/`conflict` → add note |
| Test matrix | Add `new_tests_added`, note coverage delta |
| New findings | Add `suggested_follow_ups` as new tasks, record `corrections_made` |
| Closed issues | Append to `docs/closed-issues.md` if exists |
| Dispatch metadata | Completed N/M, tests pass/total, models used, conflicts, follow-ups |
| Learning (MCP) | Fire-and-forget trajectory steps — `references/mcp-integration.md` |

## Step G — COMMIT + PUSH

1. **Full test suite** — cross-agent integration check (agent results advisory only)
2. Failures → fix directly, selective rollback (`references/saga-rollback.md`), or full rollback to `DISPATCH_BASE_SHA`
3. `git diff --stat` — verify expected files, no secrets
4. Pre-commit formatters modify files → re-stage, retry. Never `--no-verify`
5. Commit (ask user first)
6. Push (ask user first)
7. Session persistence if enabled — `references/session-persistence.md`

---

## Quick Reference

Flow: 0 → A → B → C → C½ → D → D½ → E → F → G + agents 1-6.
User gates: 0 (commit/push), C (plan), C½ (mode), G (commit/push).

## Agent Type Routing

| Task contains | Agent type | Lifecycle |
|--------------|-----------|-----------|
| test, coverage, spec | `tdd-guide` | full |
| security, auth, credential | `security-reviewer` | full |
| refactor, clean, dead code | `refactor-cleaner` | full |
| performance, optimize | `performance-optimizer` | full |
| trading, financial | `check-trading` first | full |
| docs, readme, comment | `doc-updater` | **light** |
| schema, migration, SQL | `database-reviewer` | full |
| investigate, audit, analyze | `Explore` | **light** |
| debug, fix, broken | `team-debugger` | full |
| default | `general-purpose` | full |

## When NOT to Use

- Single task — just implement directly
- Circular dependencies that can't be broken
- Real-time coordination needed (chat, shared state)
- Fewer than 2 tasks — overhead exceeds benefit

## Common Mistakes

See `references/common-mistakes.md`. Top reminders:
- **#1 failure: plan-only agents** — mitigated by implementation gate + auto re-dispatch (1 retry)
- Orchestrator NEVER implements (except fallback after re-dispatch also fails)
- NEVER auto-push — ask user first
- Agents drop sub-tasks silently — grep before committing
- Default `file-ownership-parallel`; worktrees opt-in via `--worktree`
- Default sonnet; opus for critical review only

## References

| File | Contents |
|------|----------|
| `references/agent-prompt.md` | Full + light + override templates, implementation gate, YAML report |
| `references/common-mistakes.md` | Observed + theoretical failure patterns |
| `references/worktree-mode.md` | Viability check, 3-way patch, Serial-Before-Parallel |
| `references/saga-rollback.md` | Selective rollback, hypothesis-driven failure analysis |
| `references/session-persistence.md` | Save/resume for multi-hour dispatches |
| `references/mcp-integration.md` | Optional MCP: claims, progress, memory, learning |

## Integration

- `parallel-worktree-tasks` — simpler variant without dependencies
- `parallel-feature-development` — file ownership strategies
- `dispatching-parallel-agents` — independence verification
- `verification-before-completion` — final quality gate
- `team-composition-patterns` — preset team configs
- `agentic-engineering` — eval-first loops, cost discipline

**Invoke:** `/parallel-task-dispatch {task-file}` | `--dry-run` | `--preset={name}` | `--worktree`
