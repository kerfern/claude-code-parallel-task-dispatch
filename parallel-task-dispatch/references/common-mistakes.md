# Common Mistakes

Learned from real dispatches. Sorted by frequency.

## Observed

| # | Mistake | Fix | Freq |
|---|---------|-----|------|
| 1 | **Agent only plans, doesn't implement** | #1 FAILURE MODE. Agents exhaust context on analysis. Mitigate: (a) use lifecycle template, (b) for ≤4-file tasks skip agents and implement directly | 7x |
| 2 | Worktree agent only planned | Base drift — use agent's plan, implement directly. Do NOT re-dispatch | 4x |
| 3 | Agent re-adds changes already on main | Include `ALREADY ON MAIN` block listing recent changes to owned files | 3x |
| 4 | `cp` from worktree to main | NEVER `cp` — worktree is on old base. Use 3-way patch | 2x |
| 5 | `git merge` on worktree branch | Agents don't commit — edits are uncommitted. Merge shows "up to date". Use patch | 2x |
| 6 | Using worktrees on feature branches | Worktrees create from DEFAULT branch. Use `file-ownership-parallel` or merge-forward | 2x |
| 7 | Agent reports "full suite passed" on a SLICE | Orchestrator MUST run actual full suite at Step G — never trust agent's `tests.result` | 1x |
| 8 | Completeness grep passes while behavior fails | Grep proves presence, not correctness. Must pair with full-suite behavioral check | 1x |
| 9 | Dispatching agents for small scope (≤4 files) | Agent burns 60K+ tokens, never implements. Implement directly for well-specified tasks | 1x |
| 10 | Trusting agent's "complete" report | Agents drop sub-tasks. Grep for each planned item before committing | 1x |
| 11 | Orchestrator implements code | Orchestrator coordinates — agents implement (except fallback) | 1x |

## Recovery Patterns

| Situation | Action |
|-----------|--------|
| Agent fix insufficient after full-suite failure | Rewrite directly — you have full context. Re-dispatch forces re-discovery | |
| Read-only validation task | Orchestrator runs directly. No subagent overhead |
| Small scope (≤4 files, plan has exact code) | Dispatch 1 Explore agent for analysis, implement directly using findings |
| No pre-existing task file | Create on-demand in `docs/superpowers/plans/` |
| Agent's scope too narrow | Specify exact test command — not "verify in full suite" |

## Theoretical (guard rails)

| Mistake | Fix |
|---------|-----|
| Agent skips red team | Steps 1-6 mandatory, in order |
| Agent fixes unrelated tests | Report pre-existing, don't fix |
| Agent silently reinterprets task | Report RED_TEAM_CONFLICT, let user decide |
| Dispatching Batch 2 before merging Batch 1 | Sequential — merge then dispatch |
| Pushing without approval | NEVER auto-push |
| Two agents write same migration number | Pre-assign in Step C |
| Multi-item prompt as prose paragraph | Number each sub-task; require per-item status |
| No-worktree agent runs full suite | Concurrent edits → false regressions. Orchestrator runs suite at G1 |
