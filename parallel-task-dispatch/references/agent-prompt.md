# Agent Lifecycle Templates

Orchestrator fills `{placeholders}` at dispatch time. Paste the full template into the agent prompt — custom instructions cause agents to only plan and not implement.

## Full Lifecycle (implementation tasks)

```markdown
You are implementing a task. Follow ALL 6 steps IN ORDER. You MUST reach Step 4 (Implement) and Step 5 (Test). Do NOT stop after planning.

STEP 1 — ANALYZE
**Task**: {task_description}
**Depends on**: {dependency_list_or_none}
**Blocks**: {blocks_list_or_none}
- Read all referenced files
- Verify dependencies exist (Glob/Grep). Missing → status: blocked
- Identify what needs changing and current state

STEP 2 — PLAN
1. Files to modify + specific changes per file
2. Order of operations
3. Verification approach (tests to run)
4. Edge cases

STEP 3 — RED TEAM
- Do files/functions actually exist at described paths?
- Will changes break anything outside owned files?
- Hidden dependencies (other code importing what you change)?
- Matches project conventions?
- Factual errors in task → report in Step 6, do NOT silently reinterpret

STEP 4 — IMPLEMENT
**Owned Files** (modify ONLY these): {file_list}
**Read-Only Files**: {read_only_list}
- Modify ONLY owned files
- Follow existing code patterns
- Need read-only file changes → describe in report

STEP 5 — TEST (eval-first gate)
5a. Run relevant tests BEFORE changes (baseline)
5b. Run same tests AFTER changes
5c. New regressions > 0 → fix. Unfixable → status: failed
Auto-detect: `.polybotenv/`→pytest, `package.json`→npm test, `Cargo.toml`→cargo test, `go.mod`→go test

STEP 6 — REPORT
```yaml
task_id: {N}
task_summary: "{one_line}"
status: completed | failed | blocked | conflict
risk_tier: critical | high | standard | low
model_used: "{model}"

analysis:
  dependencies_verified: true | false | "missing: X"
  files_examined: [list]

plan:
  files_and_changes: ["file: change"]
  order: [file list]
  verification: "{how}"
  edge_cases: ["case"]

red_team:
  all_facts_verified: true | false
  conflicts: ["RED_TEAM_CONFLICT: ..."]
  corrections_made: ["desc"]
  hidden_dependencies_found: ["desc"]
  regression_risk: none | low | medium | high

implementation:
  files_modified: ["path (+N/-N)"]
  files_created: ["path"]
  approach: "{brief}"

tests:
  command: "{what ran}"
  baseline: {passed: N, failed: N}
  result: {passed: N, failed: N}
  new_regressions: N
  new_tests_added: ["name: coverage"]
  pre_existing_failures: ["test_name"]

bookkeeping:
  suggested_follow_ups: ["desc"]
  cross_task_needs:
    - {task_id: N, need: "what", blocking: true|false}
  task_file_notes: "{notes}"
```
```

## Light Lifecycle (research/docs — no code changes)

```markdown
You are performing a research/analysis task. Follow these 3 steps.

STEP 1 — ANALYZE
**Task**: {task_description}
- Read referenced files, identify scope, note current state

STEP 2 — FINDINGS
1. Key findings with file:line citations
2. Recommendation
3. Risk assessment

STEP 3 — REPORT
```yaml
task_id: {N}
task_summary: "{one_line}"
status: completed | blocked
findings:
  files_examined: [list]
  key_findings: ["finding with citation"]
  recommendation: "{action}"
  risk_assessment: "{risk}"
bookkeeping:
  suggested_follow_ups: ["desc"]
```
```

## Placeholders

| Placeholder | Source |
|------------|--------|
| `{task_description}` | Step A |
| `{dependency_list_or_none}` | Step B |
| `{blocks_list_or_none}` | Step B |
| `{file_list}` | Step C |
| `{read_only_list}` | Step C |
