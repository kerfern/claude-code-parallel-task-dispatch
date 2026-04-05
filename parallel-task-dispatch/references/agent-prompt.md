# Agent Lifecycle Prompt Template

Each agent dispatched by `parallel-task-dispatch` receives this 6-step template as its
full instruction set. Orchestrator fills in `{placeholders}` at dispatch time, one per task.

```markdown
You are implementing a task{" in an isolated git worktree" | ""}. Follow
these 6 steps IN ORDER. Do not skip any step.

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
STEP 2 — PLAN
═══════════════════════════════════════════════════════════════

Produce an explicit plan before red-teaming or writing code:

1. **Files to modify** — list each owned file + the change it needs
2. **Order of operations** — which file first? Any inter-change dependencies?
3. **Specific changes** — function names, signatures, key logic edits
4. **Verification approach** — how will you know the change works? Tests to run?
5. **Edge cases** — what inputs/states might break?

Write the plan as structured notes (list or bullets). Do not skip to code —
planning forces you to think through all files and interactions before committing.

A weak plan causes surprises at Step 5 (Test). A strong plan makes Step 4
(Implement) mostly mechanical.

═══════════════════════════════════════════════════════════════
STEP 3 — RED TEAM YOUR PLAN
═══════════════════════════════════════════════════════════════

Challenge the plan from Step 2 before implementing:

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
reality, record it in your Step 6 report under `red_team.conflicts`.
The orchestrator will ask the user before merging.

═══════════════════════════════════════════════════════════════
STEP 4 — IMPLEMENT
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
STEP 5 — TEST (eval-first gate)
═══════════════════════════════════════════════════════════════

**5a. Baseline snapshot (BEFORE your changes — run first):**
Run tests relevant to your changes and record pass/fail counts.
This establishes what was already broken vs what you broke.

Auto-detect test command if no hint given:
- `.polybotenv/` or `pytest.ini` → `.polybotenv/bin/python -m pytest --timeout=30`
- `package.json` → `npm test`
- `Cargo.toml` → `cargo test`
- `go.mod` → `go test ./...`
- None found → report `tests.command: "none detected"`

**5b. Post-implementation tests (AFTER your changes):**
- Run the same test command again
- Compare: new failures = your regressions; pre-existing failures = not yours
- If your changes add new functionality, write tests for it
- If tests fail that are unrelated to your changes, note them as
  pre-existing — do NOT fix unrelated tests

**5c. Eval gate:**
- If new regressions > 0: attempt to fix. If fix fails, set
  `status: failed` with regression details. Do NOT submit broken code.
- If all new tests pass + no new regressions: proceed to Step 6

═══════════════════════════════════════════════════════════════
STEP 6 — REPORT
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
plan:
  files_and_changes: ["file: change" list]
  order: [file list or null]
  verification: "{how you'll know it works}"
  edge_cases: ["case" list or empty]

# Step 3 findings
red_team:
  all_facts_verified: {true | false}
  conflicts: ["RED_TEAM_CONFLICT: ..." or empty]
  corrections_made: ["description" or empty]
  hidden_dependencies_found: ["description" or empty]
  regression_risk: {none | low | medium | high}

# Step 4 results
implementation:
  files_modified: ["path (+lines/-lines)" list]
  files_created: ["path" list or empty]
  files_read: ["path" list]
  approach: "{brief description}"

# Step 5 results (eval-first gate)
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

## Placeholders

| Placeholder | Filled by |
|------------|-----------|
| `{task_description}` | Step A parsing |
| `{dependency_list_or_none}` | Step B dependency graph |
| `{blocks_list_or_none}` | Step B dependency graph |
| `{file_list}` | Step C ownership matrix |
| `{read_only_list}` | Step C ownership matrix |
