---
name: parallel-task-dispatch
description: Dispatch 2+ tasks as parallel agents. Full lifecycle (analyze→plan→red-team→implement→test→report) or light (analyze→findings→report). Handles deps, file ownership, risk scoring, batching, merge, saga rollback, and commit.
---

# Parallel Task Dispatch

**Source:** https://github.com/kerfern/claude-code-parallel-task-dispatch — `/update-parallel-task-dispatch` to pull latest.

## Architecture

```
ORCHESTRATOR                    AGENTS (per-task)
================                ================
0. Pre-flight: auto-commit      1. Analyze
A. Parse + risk-score           2. Plan
B. Dependency graph             3. Red team
C. Ownership + model            4. Implement
C½. Mode (parallel|serial)      5. Test (eval-first)
D. Dispatch (one message)       6. Report (YAML)
D½. Monitor
E. Merge + batch gate
F. Bookkeep
G. Commit (auto) + push (ask)
```

Steps 1–6 per agent (full) or 1–2+6 (light: research, docs). Orchestrator implements only on agent failure.

## Modes

| Mode | When | Default |
|------|------|---------|
| `file-ownership-parallel` | Disjoint files | YES |
| `serial-batches` | Overlapping files | — |
| `worktree-parallel` | `--worktree` flag + main branch | — |
| Config mode | Files outside git | auto |

Optional MCP layers (claims/rebalance, progress, session, learning) — see `references/mcp-integration.md`.

## Team Presets

| Preset | Agents | Use |
|--------|--------|-----|
| `feature` | 1 lead + 2–3 impl | Multi-file feature |
| `review` | 3–5 reviewers | Security/perf/arch audit |
| `debug` | 3 debuggers (ACH) | Multi-hypothesis bug |
| `fullstack` | frontend + backend + API + test | Cross-layer |
| `migration` | 2 impl + 1 reviewer | Framework upgrade |
| `research` | 3–5 Explore agents | Investigation |

---

## Step 0 — Pre-Flight

Auto-commit dirty tracked files (skip `.claude/settings*`, `.env*`, lockfiles, gitignored). Stage explicit paths — never `-A`/`.`. Pre-commit hook is the secret gate. Save `git rev-parse HEAD` as `DISPATCH_BASE_SHA`. Worktree mode: viability check (`references/worktree-mode.md`). Never auto-push.

## Step A — Parse + Risk Score

Per task: `depends on`, `blocks`, priority (`P0/1/2`), status (skip done).

| Tier | Keywords | Model | Gate |
|------|----------|-------|------|
| Critical | auth, payment, trading, credential, secret | sonnet (opus review) | security-reviewer |
| High | migration, schema, delete, refactor, breaking | sonnet | full suite + diff |
| Standard | feature, bugfix, implementation | sonnet | batch gate |
| Low | docs, comment, readme, config, typo | sonnet | ownership only |
| Research | investigate, audit, analyze, benchmark | sonnet (Explore) | report only — no merge |

## Step B — Dependency Graph

Topological sort → batches. Circular deps → show cycle, ask which edge to remove. Highlight critical path.

## Step C — Ownership + Model

One owner per file. Show plan table `| # | Task | Batch | Risk | Model | Agent | Owned | Read-Only |`.

Same-batch overlap → priority gets write, other read-only (or serial). Migrations → pre-assign numbers from current schema. Research agents skip ownership. Sonnet default; opus only for critical review.

Auto-dispatch after table. Halt list in **Halts** section below.

## Step C½ — Mode

| File overlap? | Mode |
|---------------|------|
| None | `file-ownership-parallel` |
| Overlap | `serial-batches` |

User may override to `worktree-parallel` (`--worktree` + Step 0 viable).

## Step D — Dispatch

All batch agents in **one** message. Each gets the full lifecycle template (`references/agent-prompt.md`) with placeholders filled. Template includes implementation gate + 3-attempt test loop.

```python
Agent(
  description="Task N: {summary}",
  prompt=FULL_LIFECYCLE_TEMPLATE,
  model="sonnet",
  run_in_background=True,
  # isolation="worktree",  # only in worktree-parallel
)
```

**Fast-path** — orchestrator implements directly when:
- Read-only task (verification, git-log, coverage report)
- ≤4 files with detailed plan already in hand

**After dispatch: stop, wait.**

### Agent return — failure-mode triage

| Symptom | Cause | Action |
|---------|-------|--------|
| Clean return, `files_modified` empty | Plan-only / dropped | Re-dispatch with override (max 1 retry) |
| Watchdog timeout, no return | Stalled mid-analysis | **Implement directly** — re-dispatch produces same paralysis |
| Output contains literal `<function_calls>` text, diff empty | Hallucinated tools | Re-dispatch warning "use real tools, not text" |
| `code_written: false` but diff non-empty | Over-conservative reporting | Trust diff, proceed |
| `status: failed` (tests exhausted) | Real fault | Read failure history, fix directly or defer |
| `status: blocked` | Dep issue | Resolve dep or defer |
| `status: completed` | OK | Verify diff matches `files_modified`, proceed |
| Files outside ownership | Ownership violation | Caught at Step E — revert + re-dispatch narrowed |
| Step G suite fails after success report | Bug or test rot | Fix directly — do NOT re-dispatch |

## Step D½ — Monitor (optional)

For 6+ agents or batches >5 min. Track returns, note blockers. MCP variant in `references/mcp-integration.md`.

## Step E — Merge + Batch Gate

Per agent return:
- Red-team conflicts → show, ask before merge
- Blocked/failed → keep open, do not merge
- Git mode: rollback tag, `git diff --stat`, ownership check
- Worktree mode: 3-way patch (`references/worktree-mode.md`)
- Config mode: backup verify, JSON/YAML validate, cross-ref links

### Batch gate (mandatory between batches)

1. All agents returned
2. Conflicts resolved
3. Merges clean
4. **Completeness**: grep planned items (function names, imports, fix tokens). Zero matches = silently dropped → implement directly
5. **Ownership**: `git diff --name-only` vs map. Unauthorized → revert
6. **Full test suite** — not agent's narrow scope
7. Worktree mode: commit + push + re-check viability
8. Re-run C½ if new tasks/reshuffling
9. Update `DISPATCH_BASE_SHA`

Cascading failures → `references/saga-rollback.md`.

## Step F — Bookkeep

| Action | Detail |
|--------|--------|
| Statuses | `completed` → done; `failed` → keep open with reason; `blocked` → note |
| Test matrix | `new_tests_added`, coverage delta |
| Findings | `suggested_follow_ups` as new tasks |
| Closed issues | Append to `docs/closed-issues.md` if exists |
| Metadata | N/M, pass/total, models, conflicts, follow-ups |
| Learning | Fire-and-forget MCP trajectory (`references/mcp-integration.md`) |

## Step G — Commit + Push

1. Full test suite (cross-agent integration; agent reports advisory)
2. Failures → fix directly, selective rollback, or full rollback to `DISPATCH_BASE_SHA`
3. `git diff --stat` — expected files, no secrets, ownership match
4. Pre-commit formatters modify files → re-stage, retry. Never `--no-verify`
5. Auto-commit when tests green. Logical commits per task group. Use HEREDOC via `/tmp/dispatch-commit-N.txt` if message contains `=`/`$` (secret-guard false-positives on inline `KEY=VALUE`)
6. Push: ask user — irreversible / shared state. Auto-push only if pre-authorized this session
7. Session persistence (`references/session-persistence.md`) if enabled

---

## Halts

These are the only prompts. Everything else auto-proceeds.

| Halt | Trigger |
|------|---------|
| Step 0 commit | pre-commit blocks; `.env` real values look staged; user said "don't commit" |
| Step C dispatch | critical-tier task; production config touch; destructive op (`DROP`, `--force`, `rm -rf`, branch delete); user said "plan only"; ≥10 files/agent or >5 batches |
| Step E batch gate | conflict needs adjudication; cascading failures → saga rollback |
| Step G commit | new test failures vs baseline; files outside ownership; secret-shaped diff; critical needs security review |
| Step G push | always |

Flow: `0 → A → B → C → C½ → D → D½ → E → F → G` + agents 1–6.

## Agent Type Routing

| Task contains | Agent | Lifecycle |
|---------------|-------|-----------|
| test, coverage, spec | `tdd-guide` | full |
| security, auth, credential | `security-reviewer` | full |
| refactor, clean, dead code | `refactor-cleaner` | full |
| performance, optimize | `performance-optimizer` | full |
| trading, financial | `check-trading` first | full |
| docs, readme, comment | `doc-updater` | light |
| schema, migration, SQL | `database-reviewer` | full |
| investigate, audit, analyze | `Explore` | light |
| debug, fix, broken | `team-debugger` | full |
| default | `general-purpose` | full |

## When NOT to Use

Single task. Unbreakable circular deps. Real-time coordination needed. Fewer than 2 tasks (overhead exceeds benefit).

## Common Mistakes

Top reminders (full list in `references/common-mistakes.md`):

- **#1 plan-only agents** → implementation gate + 1 retry override
- **#2 stalled agents** → implement directly, do NOT re-dispatch
- **#3 hallucinated tool-call text** → re-dispatch with explicit "use tools" warning
- Orchestrator implements only on agent failure (or fast-path scope)
- Auto-commit OK; auto-push never
- Verify `git diff --stat` matches agent's `files_modified` — agents over- and under-report
- Default `file-ownership-parallel`; worktrees opt-in via `--worktree`
- Default sonnet; opus only for critical review

## References

| File | Contents |
|------|----------|
| `references/agent-prompt.md` | Full + light + override templates, gate, YAML schema |
| `references/common-mistakes.md` | Observed + theoretical failure patterns |
| `references/worktree-mode.md` | Viability check, 3-way patch, Serial-Before-Parallel |
| `references/saga-rollback.md` | Selective rollback, hypothesis-driven analysis |
| `references/session-persistence.md` | Save/resume for multi-hour dispatches |
| `references/mcp-integration.md` | Optional MCP: claims, progress, memory, learning |

## Integration

`parallel-worktree-tasks` (no deps) · `parallel-feature-development` (ownership) · `dispatching-parallel-agents` (independence) · `verification-before-completion` (final gate) · `team-composition-patterns` (presets) · `agentic-engineering` (eval-first, cost discipline)

**Invoke:** `/parallel-task-dispatch {task-file}` | `--dry-run` | `--preset={name}` | `--worktree`
