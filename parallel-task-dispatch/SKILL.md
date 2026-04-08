---
name: parallel-task-dispatch
description: Use when you have a task list file with 2+ tasks to implement in parallel. Each agent runs a full 6-step lifecycle (analyze, plan, red-team, implement, test, report) or a light 3-step lifecycle (analyze, plan, report) for research/docs. Orchestrator handles dependency graphs, file ownership, model routing, merge/reconcile, task file updates, and commit+push. Supports claims-based work stealing, team presets, eval-first gates, risk scoring, session persistence, and saga rollback. Auto-detects git vs config mode. Triggers on "run tasks in parallel", "dispatch task list", "work through issues list". Not for single tasks.
---

# Parallel Task Dispatch

**Source:** https://github.com/kerfern/claude-code-parallel-task-dispatch — run `/update-parallel-task-dispatch` to pull the latest version.

## Architecture

Three layers — **orchestrator** (you), **agents** (per-task), and **coordination** (MCP-backed):

```
ORCHESTRATOR (shared state)          AGENTS (per-task)
================================     ================================
0. Pre-flight — clean tree,          1. Analyze — read issue, check
   commit + push                        depends/blocks, verify facts
A. Parse task file + risk score      2. Plan — files/changes, order,
B. Build dependency graph               verification, edge cases
C. Assign file ownership + model     3. Red team — challenge plan,
C½. Execution mode check                verify assumptions
D. Dispatch parallel batches    →    4. Implement — write code/config
D½. Monitor + rebalance        ↔     5. Test — eval-first gates
E. Merge/validate results     ←     6. Report — structured output
F. Bookkeep task file + learn           for orchestrator steps E-G
G. Commit + push

         COORDINATION (MCP-backed, optional)
         ====================================
         See references/mcp-integration.md
```

**Steps 1-6 are per-agent** (full lifecycle) or **Steps 1-2+6** (light lifecycle for research/docs). The orchestrator never implements — it coordinates.

### Execution Modes

| Mode | When | Isolation | Rollback |
|------|------|-----------|----------|
| **`file-ownership-parallel`** | Disjoint files, any risk (DEFAULT) | File ownership only | `git tag` + `git reset` |
| **`serial-batches`** | Overlapping files | Sequential batches | `git tag` + `git reset` |
| **`worktree-parallel`** | Explicit `--worktree` + on main branch | `isolation: "worktree"` | `git tag` + patch rollback |
| **Config** | Files outside git (`~/.claude/`) | File ownership only | Timestamped backups |

### Capability Layers

| Layer | Steps | Requires | Default |
|-------|-------|----------|---------|
| **Core** | 0, A, B, C, C½, D-G + Agent lifecycle | Claude Code Task tool | Always on |
| **Execution mode check** | C½ | — | On — selects mode (user-overridable) |
| **Model routing** | C, D | — | On (built into agent params) |
| **Risk scoring** | A, C | — | On (keyword heuristic) |
| **Eval-first gates** | Agent 5 | — | On (tests before + after) |
| **Worktree isolation** | 0, D, E | `--worktree` flag | Off — see `references/worktree-mode.md` |
| **Claims & rebalance** | D½ | `mcp__claude-flow__claims_*` | Off — activate for 6+ agents |
| **Progress tracking** | D½ | `mcp__claude-flow__progress_*` | Off — activate for 3+ batches |
| **Session persistence** | 0, G | `mcp__claude-flow__session_*` | Off — see `references/session-persistence.md` |
| **Learning loop** | F, G | `mcp__claude-flow__hooks_intelligence_*` | Off — activate to improve future routing |

---

## Team Presets

For common task shapes, use a preset instead of building from scratch:

| Preset | Agents | Topology | When to Use |
|--------|--------|----------|-------------|
| **feature** | 1 lead + 2-3 implementers | hierarchical | Multi-file feature implementation |
| **review** | 3-5 parallel reviewers | flat | Security + performance + architecture audit |
| **debug** | 3 parallel debuggers | flat (ACH) | Complex bug with multiple hypotheses |
| **fullstack** | frontend + backend + API + test | hierarchical | Cross-layer feature |
| **migration** | 2 implementers + 1 reviewer | pipeline | Framework upgrade, API version bump |
| **research** | 3-5 Explore agents | flat | Investigation, audit, data analysis |

**To use a preset**, add `preset: feature` (or similar) to your dispatch invocation.

---

## Orchestrator Step 0 — PRE-FLIGHT

**Run these checks in parallel:**

```bash
git status --short                    # uncommitted changes?
git log @{u}..HEAD --oneline 2>&1    # unpushed commits?
git diff --stat                       # unstaged changes?
```

**Decision matrix:**

| Uncommitted changes? | Unpushed commits? | Action |
|----------------------|-------------------|--------|
| No | No | Proceed to Step A |
| Yes | — | **STOP.** Show `git status`. Ask: "Commit before dispatch?" If yes, stage + commit + re-check. If no, abort. |
| — | Yes | **STOP.** Show unpushed commits. Ask: "Push before dispatch?" If yes, push. If no, proceed with caution. |

**Rules:**
- NEVER auto-commit or auto-push — always ask the user
- Untracked files are fine — only tracked modifications matter
- Config mode (files outside git) skips git checks entirely

**After clean state confirmed:**
```bash
git rev-parse HEAD   # save as DISPATCH_BASE_SHA for rollback reference
```

**Worktree mode only:** If `--worktree` flag is set, run the full viability check from `references/worktree-mode.md` (feature-branch detection, merge-forward option, Serial-Before-Parallel Invariant). Worktree mode requires being on the default branch or having merged forward.

## Orchestrator Step A — PARSE + RISK SCORE

Read the task list file. Extract per task:

| Field | Look for | Effect |
|-------|---------|--------|
| Depends on | `depends on: #N`, `after: #N`, `requires: #N` | Cannot start until dependency completes |
| Blocks | `blocks: #N`, `before: #N` | Dependents wait |
| Priority | `P0/P1/P2`, `priority: high/med/low` | Order within batch |
| Status | `[x]`, `DONE`, `CLOSED` | Skip |

**Risk scoring (per task):**

| Risk Tier | Keywords / Signals | Model | Review Gate |
|-----------|-------------------|-------|-------------|
| **Critical** | "auth", "payment", "credential", "secret", "trading", "order", "financial" | opus or sonnet | Mandatory security-reviewer post-merge |
| **High** | "migration", "schema", "delete", "remove", "refactor", "breaking" | sonnet | Full test suite + diff review |
| **Standard** | Implementation, feature, bugfix | sonnet | Standard batch gate |
| **Low** | "docs", "comment", "readme", "typo", "config" | sonnet | Minimal — ownership check only |
| **Research** | "investigate", "audit", "analyze", "measure", "benchmark" | sonnet (Explore agent) | No merge — report only |

## Orchestrator Step B — DEPENDENCY GRAPH

- Topological sort tasks into parallel batches
- Batch 1: no dependencies (run in parallel)
- Batch 2: depends on Batch 1 results (run after Batch 1 merges)
- Circular dependencies: show cycle to user, ask which edge to remove, re-sort

**Critical-path highlight:** Identify the longest dependency chain and show it in the
execution plan.

## Orchestrator Step C — FILE OWNERSHIP + MODEL ROUTING

Per task, identify target files (from description or grep/glob). Build ownership matrix — one owner per file. Present execution plan:

```
EXECUTION PLAN
==============
Batch 1 (parallel): #1[sonnet], #3[sonnet], #5[sonnet/explore]
Batch 2 (after #1):  #2[sonnet] (depends on #1)

| # | Task | Batch | Risk | Model | Agent Type | Prompt | Owned Files | Read-Only |
|---|------|-------|------|-------|------------|--------|-------------|-----------|
| 1 | Add auth | 1 | Critical | sonnet | general | full | src/auth.py | src/config.py |
| 3 | Fix typo | 1 | Low | sonnet | general | full | docs/api.md | — |
| 5 | Audit perf | 1 | Research | sonnet | Explore | light | — (read-only) | src/**/*.py |
| 2 | Rate limit | 2 | High | sonnet | general | full | src/middleware.py | src/auth.py |
```

**Overlap detection:** If a file appears in 2+ tasks within the same batch, assign to higher-priority task; other gets read-only. If both MUST write, split into sequential batches.

**Migration number coordination:** If multiple tasks add migrations, pre-assign numbers
in the plan based on the current schema version. Tell each agent its number explicitly.

**Research-only agents:** Dispatch WITHOUT `isolation: "worktree"` — they don't modify files.

**Model routing:** Sonnet is the default for all agent roles. Use opus only for complex
architectural reasoning or security-critical review.

**User approves before dispatch.**

## Orchestrator Step C½ — EXECUTION MODE CHECK

Evaluated after Step C (file ownership known). Default is `file-ownership-parallel`.

| File overlap? | Execution mode |
|---------------|----------------|
| None (disjoint) | **`file-ownership-parallel`** (default) |
| Overlap exists | **`serial-batches`** — split overlapping tasks into sequential batches |

Show mode before dispatch with override options:
```
Execution mode: file-ownership-parallel
  Reason: all owned-file sets disjoint
  Override:
    [A] Accept (proceed to Step D)
    [B] Force worktree-parallel (requires --worktree + main branch)
    [C] Abort dispatch
```

**Worktree override:** Option [B] activates full worktree isolation. Requires
`WORKTREE_VIABLE=true` from Step 0. See `references/worktree-mode.md` for viability
check, 3-way patch merge protocol, and Serial-Before-Parallel Invariant.

## Orchestrator Step D — DISPATCH

**All agents in a batch dispatched in ONE message.** Each agent receives its lifecycle
prompt. **Dispatch mode is set by Step C½.**

### Agent Prompt Selection

| Agent type | Prompt template | Steps |
|-----------|----------------|-------|
| Implementation (writes code) | **Full** — `references/agent-prompt.md` | 1-6: Analyze → Plan → Red Team → Implement → Test → Report |
| `Explore`, `doc-updater`, research | **Light** — `references/agent-prompt.md` (light variant) | 1-2+6: Analyze → Plan → Report |

Light agents skip Red Team (Step 3), Implement (Step 4), and Test (Step 5). Their Plan
step becomes "what did you find + recommendation" rather than "what will you change."

### Dispatch Template

```
Agent(
  description="Task N: {summary}",
  prompt=AGENT_LIFECYCLE_PROMPT,     # full or light per table above
  isolation="worktree",              # ONLY when worktree-parallel mode
  model="{risk-based model from Step C}",
  run_in_background=true
)
```

Drop `isolation="worktree"` in `file-ownership-parallel` and `serial-batches` modes.

**STOP after dispatch.** Wait for all agents in the batch to return.

**Post-dispatch validation:**
When an agent returns, check for:
1. Agent only planned but didn't implement → base drift (worktree mode) or agent error. Use plan as instructions, implement directly.
2. Agent `status: blocked` with "dependency missing" → check if dependency was completed
3. Agent modified files outside ownership → will be caught at Step E ownership check

**Worktree-specific dispatch rules** (ALREADY-ON-MAIN context, cwd hygiene, rate limits):
see `references/worktree-mode.md`.

---

## Orchestrator Step D½ — MONITOR + REBALANCE (optional)

**When to activate:** 6+ agents dispatched, or batch expected to take >5 minutes.
Runs WHILE agents are working — does NOT block execution.

**Without MCP (lightweight):**
- Track which agents have returned vs. still running
- If an agent returns `status: blocked`, note it for Step E
- If an agent returns much faster than others, note for future batch sizing

**With claims MCP:** see `references/mcp-integration.md` for work-stealing protocol.

---

## Agent Lifecycle

Each agent receives its lifecycle template embedded in the dispatch prompt.

**Full lifecycle** (implementation tasks): Analyze → Plan → Red Team → Implement → Test → Report.
**Light lifecycle** (research/docs tasks): Analyze → Plan → Report.

Full template with placeholders and YAML report schema: see `references/agent-prompt.md`.

## Orchestrator Step E — MERGE / VALIDATE

After all agents in a batch return:

**Check for red team conflicts first:**
- Any `RED_TEAM_CONFLICT`? → Show to user, ask before merging
- Any `status: blocked`? → Don't merge, keep task open
- Any `status: failed`? → Check if isolated or systemic

### Git Mode (file-ownership-parallel / serial-batches)

1. Create rollback tag: `git tag pre-parallel-merge-$(date +%s)`
2. Review each agent's changes via `git diff --stat`
3. Run ownership check (see Pre-commit Verification below)
4. If all clean: stage and proceed to batch gate

### Git Mode (worktree-parallel)

Worktree branches may be on a stale base — use the 3-way patch merge protocol from
`references/worktree-mode.md`. Never use `git merge` or `cp` from worktree to main.

### Config Mode

1. **Verify backups exist** (created pre-dispatch: `cp -p {file} /tmp/parallel-config-backup-{ts}/`)
2. **Ownership check**: compare files modified vs ownership list
3. **Validate by type:**
   - `.json` → `python -c "import json; json.load(open('f'))"`
   - `.yaml`/`.yml` → `python -c "import yaml; yaml.safe_load(open('f'))"`
   - `.md` with frontmatter → verify `---` delimiters + required fields
4. **Cross-ref check**: verify links/references between files are consistent
5. **If invalid**: show error, offer per-file selective restore from backup

### Multi-Agent Failure Recovery

For cascading failures (agent A breaks agent B) or ambiguous test failures, see
`references/saga-rollback.md` for selective rollback protocol and hypothesis-driven
failure analysis.

### BATCH GATE (mandatory between batches)

1. All agents in current batch returned? If not, STOP.
2. All `red_team.conflicts` resolved with user? If not, ask.
3. All merges completed without conflict? If not, resolve.
4. **Completeness check passed** (see below)? If not, implement missing items.
5. **Ownership check passed** (see below)? If not, revert unauthorized files.
6. Full test suite passes? If not, fix or rollback.
7. **Sync for next batch** (worktree mode only): commit + push, re-run Step 0 viability.
8. **Re-run Step C½** if batch N added new tasks or reshuffled file ownership.
9. Update DISPATCH_BASE_SHA to post-push HEAD.

Only then: dispatch next batch.

### Pre-commit Verification (mandatory)

Agent self-reports are unreliable. Two grep-based checks before committing:

**Completeness check** — agents silently skip sub-tasks from multi-item prompts.
Extract a greppable token from each plan item, grep for it:

| Plan item | Greppable token |
|-----------|----------------|
| New event/function | exact string, e.g. `"candidate_decision"` |
| Bug fix `X → Y` | `Y` must exist **and** `X` must not |
| New import | full import line |
| New config field | field name |

Zero matches = silently dropped. Implement directly or re-dispatch a narrow agent.

**Ownership check** — agents modify files beyond their declared ownership:

```bash
EXPECTED="fileA.py fileB.py strategy/fileC.py"
git diff --stat --name-only | while read f; do
    case " $EXPECTED " in *" $f "*) ;; *) echo "UNAUTHORIZED: $f" ;; esac
done
```

Unauthorized files → `git checkout` to revert (common case), or show diff to user.

## Orchestrator Step F — BOOKKEEP + LEARN

Update the **original task list file** using agent reports:

**F1. Task statuses:**
- `completed` → update using file's format (`- [ ]`/`- [x]`, status field, or headers)
- `failed` → add `(FAILED: reason)`, keep open
- `blocked` → keep as-is, add note
- `conflict` → add `(NEEDS REVIEW: description)`, keep open

**F2. Test matrix** (if the file has one): add `new_tests_added`, note coverage changes.

**F3. New findings:** add `suggested_follow_ups` as new tasks, annotate `hidden_dependencies_found`, record `corrections_made`.

**F4. Closed issues update:** for completed tasks, append to `docs/closed-issues.md` (if it exists) and remove from open issues file.

**F5. Dispatch metadata:**
```markdown
## Last Dispatch — {date}
- Completed: {N}/{total}
- Tests: {pass}/{total} ({new_tests} new)
- Models: {sonnet: N, opus: N}
- Conflicts: {list or "none"}
- Follow-ups added: {N}
```

**F6. Learning loop (if MCP tools available):** fire-and-forget trajectory steps and model outcomes. See `references/mcp-integration.md`.

## Orchestrator Step G — COMMIT + PUSH

**G1. Run full test suite** (cross-agent integration check):
```bash
.polybotenv/bin/python -m pytest --timeout=30   # or project equivalent
```

Agent test results are advisory, not authoritative. The orchestrator's G1 run is the
only reliable integration check.

**G2. If new failures:** identify which agent's changes caused it → offer:
  - **Fix agent**: targeted fix for the specific failure
  - **Selective rollback**: revert just that agent's changes (see `references/saga-rollback.md`)
  - **Full rollback**: revert to `DISPATCH_BASE_SHA` tag

**G3. Stage + review:** `git diff --stat` — verify only expected files, no secrets.

**G4. Pre-commit formatter handling:**
If auto-formatters (ruff-format, black, prettier) in pre-commit hooks modify files,
re-stage and retry: `git add -u && git commit -m "..."`. Do NOT use `--no-verify`.

**G5. Commit:**
```bash
git commit -m "$(cat <<'EOF'
feat: parallel dispatch — {summary}

Tasks completed:
{per-task one-liner from agent reports}

Tests: {pass}/{total} ({new} new)
Models: {sonnet: N, opus: N}
Mode: {Git|Config}

Co-Authored-By: {current_model} <noreply@anthropic.com>
EOF
)"
```

**G6. Push** only if user has approved.

**G7. Session persistence** (if enabled): see `references/session-persistence.md`.

---

## Quick Reference

Flow: 0 → A → B → C → C½ → D → D½ → E → F → G (orchestrator) + 1-6 per agent.
User gates: Step 0 (commit/push), C (plan), C½ (mode), G (push).

## Agent Type Routing

Auto-select based on task content and risk tier:

| Task contains | Agent type | Prompt | Default Model |
|--------------|-----------|--------|---------------|
| "test", "coverage", "spec" | `tdd-guide` | full | sonnet |
| "security", "auth", "credential" | `security-reviewer` | full | sonnet |
| "refactor", "clean", "dead code" | `refactor-cleaner` | full | sonnet |
| "performance", "optimize", "benchmark" | `performance-optimizer` | full | sonnet |
| Trading/financial logic | `check-trading` first | full | sonnet |
| "docs", "readme", "comment" | `doc-updater` | **light** | sonnet |
| "schema", "migration", "query", "SQL" | `database-reviewer` | full | sonnet |
| "investigate", "audit", "analyze", "measure" | `Explore` (read-only) | **light** | sonnet |
| "debug", "fix", "broken", "failing" | `team-debugger` | full | sonnet |
| Multiple categories match | Priority: trading > security > tdd > general | full | highest-risk model |
| Everything else | `general-purpose` | full | sonnet |

## When NOT to Use This Skill

- Single task — just implement it directly
- Tasks have circular dependencies that can't be broken
- Tasks require real-time coordination (chat, shared state)
- Fewer than 2 tasks — overhead exceeds benefit
- (Note: all tasks touching the same file is fine — `serial-batches` mode handles it)

## Common Mistakes

Learned patterns from past dispatches — sorted by observed frequency.
Full table: see `references/common-mistakes.md`.

**Top 5 reminders:**
- Orchestrator NEVER implements — agents do
- NEVER auto-push; ask user first
- Agents drop sub-tasks silently — grep for each planned item before committing
- Default to `file-ownership-parallel`; worktrees are opt-in via `--worktree`
- Default to sonnet; reserve opus for critical architecture/security review

## References

| File | Contents |
|------|----------|
| `references/agent-prompt.md` | Full + light agent lifecycle templates, YAML report schema, placeholders |
| `references/common-mistakes.md` | All observed and theoretical mistakes with frequency/recency |
| `references/worktree-mode.md` | Viability check, merge-forward, 3-way patch protocol, Serial-Before-Parallel Invariant |
| `references/saga-rollback.md` | Selective rollback protocol, hypothesis-driven failure analysis |
| `references/session-persistence.md` | Resume/save checkpoints for multi-hour dispatches |
| `references/mcp-integration.md` | Optional MCP tools: claims, progress, shared memory, learning |

## Integration

- **parallel-worktree-tasks** — simpler variant without dependencies; config mode backup protocol
- **parallel-feature-development** — file ownership strategies, interface contracts
- **dispatching-parallel-agents** — independence verification, when NOT to parallelize
- **verification-before-completion** — final quality gate before claiming done
- **team-composition-patterns** — preset team configurations for common scenarios
- **agentic-engineering** — eval-first loops, 15-minute unit rule, cost discipline

**Invoked via:** `/parallel-task-dispatch {task-list-file}` or `--dry-run` or `--preset={name}` or `--worktree`
