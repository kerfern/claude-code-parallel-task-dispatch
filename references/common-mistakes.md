# Common Mistakes

Sorted by observed frequency. Referenced from `SKILL.md`.

## Observed

| Mistake | Fix | Freq | Last |
|---------|-----|------|------|
| **Agent only plans, doesn't implement** | **#1 FAILURE MODE.** Custom instruction prompts cause agents to stop at Step 2. MUST embed the full lifecycle template from `agent-prompt.md` with placeholders filled. | 6x | Apr 9 |
| **Agent reports "full suite passed" on a SLICE** | Agent runs tests in its narrow scope and calls it "full suite". Orchestrator MUST run the ACTUAL full suite at Step G, not trust the agent's `tests.result` field. | 1x | Apr 10 |
| **Completeness grep passes while behavior fails** | Grep proves presence, not correctness. A setUp/tearDown can be present (grep ✓) while still not fixing the underlying isolation problem. Completeness check is necessary but not sufficient — Step G's full-suite run is the behavioral check. | 1x | Apr 10 |
| Worktree agent "only planned, didn't implement" | Base drift — use agent's plan, implement directly. Do NOT re-dispatch with worktrees. | 4x | Apr 4 |
| Agent re-adds migration/changes already on main | Include `ALREADY ON MAIN` block listing recent changes to owned files. | 3x | Apr 4 |
| `cp` from worktree to main tree | NEVER `cp` — worktree is on old base. Use 3-way patch. | 2x | Apr 3 |
| `git merge` on worktree branch | Agent edits are uncommitted. Merge shows "up to date". Use patch. | 2x | Apr 3 |
| Trusting agent's "complete" report | Agents drop sub-tasks. Grep for each planned item before committing. | 1x | Apr 4 |
| Orchestrator implements code | Orchestrator coordinates — agents implement (except fallback). | 1x | Apr 4 |

## Recovery Patterns

| Situation | Best action |
|-----------|-------------|
| Agent fix insufficient after Step G full-suite failure | Rewrite directly in orchestrator — you have full context of the failure mode. Re-dispatching forces the new agent to re-discover the bug. |
| Read-only validation task (final test run, etc.) | Orchestrator runs directly. No subagent overhead. |
| No pre-existing plan/task file | Create task file on-demand in `docs/superpowers/plans/YYYY-MM-DD-<name>.md` with the same structure. |
| Agent's scope was too narrow | When dispatching, specify "run THIS command: `<full-suite-cmd>`" — not "verify in full suite". Agents interpret "full suite" as their own scope. |

## Theoretical (guard rails)

| Mistake | Fix |
|---------|-----|
| Agent skips red team | Steps 1-6 mandatory in order |
| Agent fixes unrelated tests | Report pre-existing, don't fix |
| Dispatching Batch 2 before Batch 1 merges | Sequential — merge then dispatch |
| Pushing without approval | NEVER auto-push |
| Two agents write same migration number | Pre-assign in Step C |
| Multi-item prompt as prose | Number each sub-task; require per-item status |
