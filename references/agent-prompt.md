# Agent Lifecycle Prompt Templates

Orchestrator fills `{placeholders}` at dispatch. **Paste the full template — custom prompts cause agents to only plan.**

## Full Lifecycle (implementation tasks)

```markdown
You are implementing a task. Follow ALL 6 steps IN ORDER.

⚠️  IMPLEMENTATION GATE
You MUST call Edit/Write in Step 4 and run tests in Step 5.
A report with zero files modified is a FAILURE — go back to Step 4.

STEP 1 — ANALYZE
**Task**: {task_description}
**Depends on**: {dependency_list_or_none}
**Blocks**: {blocks_list_or_none}
- Read referenced files, verify dependencies (Glob/Grep). Missing → status: blocked
- ⏱ Spend ≤20% of effort on Steps 1-3. Implementation is the deliverable.

STEP 2 — PLAN
1. Files to modify + specific changes
2. Order of operations
3. Test command to verify

STEP 3 — RED TEAM (brief)
- Paths/functions exist? Breaking changes outside owned files?
- Factual errors → RED_TEAM_CONFLICT, do NOT reinterpret

STEP 4 — IMPLEMENT ← mandatory
**Owned files** (modify ONLY these): {file_list}
**Read-only files**: {read_only_list}
- Call Edit or Write on owned files. This step is not optional.
- Follow existing patterns. Need read-only changes → note in report.

STEP 5 — TEST + ITERATE (max 3 attempts)
Auto-detect: `.polybotenv/`→pytest, `package.json`→npm test, `Cargo.toml`→cargo test, `go.mod`→go test

  attempt 1: run tests → pass? done. fail? diagnose + fix ↓
  attempt 2: run tests → pass? done. fail? diagnose + fix ↓
  attempt 3: run tests → pass? done. fail? → status: failed

Record per attempt: failures, fix applied, result.

STEP 6 — REPORT
Self-check before reporting: did you call Edit/Write in Step 4?
If not → STOP, go back to Step 4. Do not file a plan-only report.

```yaml
task_id: {N}
task_summary: "{one_line}"
status: completed | failed | blocked

implementation_gate:
  code_written: true | false
  files_modified_count: N
  test_attempts: N
  final_pass: true | false

plan:
  files_and_changes: ["file: change"]

red_team:
  all_facts_verified: true | false
  conflicts: ["RED_TEAM_CONFLICT: ..."]

implementation:
  files_modified: ["path (+N/-N)"]
  approach: "{brief}"

tests:
  command: "{cmd}"
  attempts:
    - {n: 1, passed: N, failed: N, fix: "null | desc"}
  final: {passed: N, failed: N, regressions: N}

bookkeeping:
  suggested_follow_ups: ["desc"]
```
```

## Override Template (re-dispatch for plan-only return)

When an agent returns without implementing (`code_written: false` or no `files_modified`),
re-dispatch ONCE with this compressed template:

```markdown
IMPLEMENTATION OVERRIDE — A prior agent analyzed this task but wrote NO code.
You must implement now. Analysis is done — skip to Step 4.

PRIOR PLAN:
{paste_agent_plan_yaml}

STEP 4 — IMPLEMENT
**Owned files**: {file_list}
**Read-only files**: {read_only_list}
Write the code. Edit/Write calls required. No further analysis.

STEP 5 — TEST + ITERATE (max 3 attempts)
  attempt 1: run tests → pass? done. fail? fix ↓
  attempt 2: run tests → pass? done. fail? fix ↓
  attempt 3: run tests → pass? done. fail? → status: failed

STEP 6 — REPORT (same YAML schema as full lifecycle)
```

Override also returns plan-only → orchestrator implements directly. Max 1 re-dispatch.

## Light Lifecycle (research/docs — no code changes)

```markdown
You are performing a research/analysis task. 3 steps.

STEP 1 — ANALYZE
**Task**: {task_description}
- Read referenced files, identify scope

STEP 2 — FINDINGS
1. Key findings with file:line citations
2. Recommendation + risk assessment

STEP 3 — REPORT
```yaml
task_id: {N}
task_summary: "{one_line}"
status: completed | blocked
findings:
  files_examined: [list]
  key_findings: ["finding with citation"]
  recommendation: "{action}"
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
| `{paste_agent_plan_yaml}` | Prior agent's plan YAML (override only) |
