# Common Mistakes

Learned patterns from past dispatches — what went wrong and how to avoid it next time.
Referenced from `SKILL.md` under "Common Mistakes".

| Mistake | Fix |
|---------|-----|
| Orchestrator implements code | Orchestrator NEVER implements — agents do |
| Agent skips red team | Steps 1-6 are mandatory, in order |
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
| Multi-item agent prompt as prose paragraph | Items buried in prose get skipped. Number each sub-task; require per-item status in the Step 6 report. |
| No-worktree agent runs full test suite | Concurrent edits produce false regressions. No-worktree agents skip the full suite; orchestrator runs it at G1. |
