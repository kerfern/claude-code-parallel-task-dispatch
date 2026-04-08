# Common Mistakes

Learned patterns from past dispatches — what went wrong and how to avoid it.
Referenced from `SKILL.md`. Sorted by observed frequency (highest first).

## Observed (confirmed in real dispatches)

| Mistake | Fix | Freq | Last |
|---------|-----|------|------|
| Worktree agent "only planned, didn't implement" | Base drift — use agent's plan, implement directly. Do NOT re-dispatch with worktrees. | 4x | Apr 4 |
| Agent re-adds migration/changes already on main | Include `ALREADY ON MAIN` block in agent prompt listing recent changes to owned files. | 3x | Apr 4 |
| `cp` from worktree to main tree | NEVER `cp` — worktree is on old base, overwrites recent changes. Use 3-way patch. | 2x | Apr 3 |
| `git merge` on worktree branch | Agents don't commit — edits are uncommitted. Merge shows "up to date". Use patch. | 2x | Apr 3 |
| Using worktrees on feature branches | Worktrees create from DEFAULT branch, not current. Use `file-ownership-parallel` (default) or merge-forward first. | 2x | Apr 4 |
| Trusting agent's "complete" report | Agents drop sub-tasks silently. Grep for each planned item before committing. | 1x | Apr 4 |
| NameError after patch apply (scope mismatch) | Agent coded against old call chain. Full test suite catches it. Fix manually. | 1x | Apr 3 |
| Running git commands after worktree `cd` | cwd silently drifts to worktree dir. ALWAYS prefix with `cd <main_tree> &&`. | 1x | Apr 3 |
| Serial work unpushed before a worktree dispatch | Commit + push to `origin/<default>` first. See Serial-Before-Parallel Invariant. | 1x | Apr 4 |
| Orchestrator implements code | Orchestrator NEVER implements — agents do. | 1x | Apr 4 |
| Skipping `git diff --stat` before commit | Agents modify files outside their ownership. Run ownership check, revert unauthorized files. | 1x | Apr 5 |

## Theoretical (guard rails, not yet observed)

| Mistake | Fix |
|---------|-----|
| Agent skips red team | Steps 1-6 are mandatory, in order |
| Agent fixes unrelated tests | Report pre-existing failures, don't fix |
| Agent silently reinterprets task | Report RED_TEAM_CONFLICT, let user decide |
| Dispatching Batch 2 before merging Batch 1 | Sequential — merge then dispatch |
| Committing without full test suite | Step G1 catches cross-agent integration issues |
| Pushing without approval | NEVER auto-push |
| Agent blocks on empty test hint | Auto-detect test command; report "none detected" if unavailable |
| Merging before all batch agents finish | BATCH GATE — all checks must pass before next batch |
| Config mode with no backup | Always create `/tmp` backup before config dispatch |
| Two agents write same migration number | Assign migration numbers in Step C based on current schema version + task order |
| Using opus when sonnet suffices | Default to sonnet for all agents. Reserve opus for critical architecture/security review. |
| Leaving main broken after partial merge | Use saga compensation — selective rollback of failing agent's patch. |
| Falling back to no-isolation when merge-forward was available | Merge-forward restores true parallel isolation — ask the user FIRST. |
| Not recording dispatch outcomes | F6 learning loop improves future model routing and agent selection. |
| Multi-item agent prompt as prose paragraph | Items buried in prose get skipped. Number each sub-task; require per-item status in report. |
| No-worktree agent runs full test suite | Concurrent edits produce false regressions. No-worktree agents skip the full suite; orchestrator runs it at G1. |
