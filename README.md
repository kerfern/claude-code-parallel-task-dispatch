# parallel-task-dispatch

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) skill for orchestrating parallel task dispatch with git worktree isolation, dependency graphs, file ownership, model routing, and MCP-backed coordination.

Turn a task list into parallel agent work — each agent runs a full 6-step lifecycle (analyze, red-team, implement, test with eval-first gates, report) while the orchestrator handles dependencies, file ownership, risk scoring, model routing, merge/reconcile, saga rollback, and commit.

## Features

### Core (always active)
- **Dependency-aware batching** — topological sort into parallel batches; respects `depends on` / `blocks` relationships with critical-path highlighting
- **File ownership enforcement** — one writer per file per batch; overlap detection with automatic resolution
- **Git worktree isolation** — each agent works in its own worktree; 3-way patch merge back to main
- **Config mode** — for files outside git (e.g. `~/.claude/`); timestamped backups + validation
- **6-step agent lifecycle** — Analyze, Red Team, Implement, Test (eval-first), Report (structured YAML)
- **Red team step** — agents challenge their own plans before coding; conflicts escalated to user
- **Eval-first test gates** — baseline snapshot before changes; regression detection after
- **Risk scoring** — auto-classifies tasks (critical/high/standard/low/research) driving model selection and review gates
- **Model routing** — sonnet default for all agents; opus for complex architecture and security-critical review
- **Saga compensation** — selective rollback of individual agent patches when merges cause failures
- **Hypothesis-driven debugging** — ACH methodology for ambiguous test failures (parallel competing hypotheses)
- **Team presets** — feature, review, debug, fullstack, migration, research compositions
- **Pre-flight checks** — ensures clean tree before dispatch; prevents worktree base drift
- **Smart merge** — handles stale worktree bases with 3-way patch protocol; never uses `cp` or naive `git merge`
- **Agent type routing** — auto-selects agent type (TDD, security, refactor, etc.) based on task content
- **Batch gates** — mandatory validation between batches (conflicts resolved, tests pass, merges clean)

### MCP-Enhanced (optional, activated when tools available)
- **Claims-based work stealing** — agents release finished work, steal from overloaded peers, auto-rebalance
- **Progress tracking** — real-time completion percentage across batches
- **Session persistence** — save/resume multi-hour dispatches across conversations
- **Hive-mind shared memory** — cross-agent state without message passing
- **Learning loop** — SONA trajectories record outcomes for future routing improvement
- **Diff risk analysis** — auto-reviewer suggestion and risk scoring per file
- **Consensus** — multi-agent voting for conflicting approaches

## Installation

### Quick Install (one command)

```bash
# Clone into your Claude Code skills directory
git clone https://github.com/kerfern/claude-code-parallel-task-dispatch.git ~/.claude/skills/claude-code-parallel-task-dispatch

# Create a symlink so Claude Code discovers the skill
ln -sf ~/.claude/skills/claude-code-parallel-task-dispatch/parallel-task-dispatch ~/.claude/skills/parallel-task-dispatch
```

### Manual Install

1. Download [`parallel-task-dispatch/SKILL.md`](parallel-task-dispatch/SKILL.md)
2. Place it at `~/.claude/skills/parallel-task-dispatch/SKILL.md`

```bash
mkdir -p ~/.claude/skills/parallel-task-dispatch
curl -o ~/.claude/skills/parallel-task-dispatch/SKILL.md \
  https://raw.githubusercontent.com/kerfern/claude-code-parallel-task-dispatch/main/parallel-task-dispatch/SKILL.md
```

### Verify Installation

Start a Claude Code session and type:

```
/parallel-task-dispatch docs/tasks.md
```

If the skill is recognized, Claude will begin the orchestration flow.

## Usage

### Basic

```
/parallel-task-dispatch path/to/task-list.md
```

### Dry Run (preview execution plan without dispatching)

```
/parallel-task-dispatch path/to/task-list.md --dry-run
```

### With Team Preset

```
/parallel-task-dispatch path/to/task-list.md --preset=feature
/parallel-task-dispatch path/to/task-list.md --preset=review
/parallel-task-dispatch path/to/task-list.md --preset=debug
```

### Task List Format

The skill parses any markdown task list. Tasks can use checkboxes, headers, or numbered items. Dependency and priority metadata is extracted automatically:

```markdown
## Open Issues

### #1 — Add user authentication
Priority: P0
Files: src/auth.py, src/middleware.py

### #2 — Add rate limiting
Priority: P1
Depends on: #1
Files: src/middleware.py, src/config.py

### #3 — Update API docs
Priority: P2
Files: docs/api.md
```

### What Happens

1. **Pre-flight** — ensures clean git tree, commits/pushes if needed (with your approval); resumes interrupted sessions
2. **Parse + risk score** — extracts tasks, dependencies, priorities; auto-classifies risk tiers
3. **Dependency graph** — topological sort into parallel batches; highlights critical path
4. **File ownership + model routing** — assigns one writer per file; selects sonnet/opus per task risk
5. **Execution plan** — shows you the plan with risk tiers, models, and ownership; you approve before dispatch
6. **Dispatch** — agents run in parallel (git worktrees or config mode)
7. **Monitor + rebalance** — optional: claims-based work stealing, progress tracking
8. **Merge** — 3-way patch protocol; saga compensation for failures; hypothesis debugging for ambiguous errors
9. **Bookkeep + learn** — updates task file with results, new findings, follow-ups; records outcomes for future routing
10. **Commit + persist** — full test suite, then commit (push only with your approval); save session state

## Architecture

```
ORCHESTRATOR (shared state)          AGENTS (per-task, isolated)
================================     ================================
0. Pre-flight — clean tree,          1. Analyze — read issue, verify
   commit + push, resume session        depends/blocks, check facts
A. Parse task file + risk score      2. Red team — challenge own plan,
B. Build dependency graph               verify files exist, check
C. Assign file ownership + model        assumptions before coding
D. Dispatch parallel batches    -->  3. Implement — write code/config
D½. Monitor + rebalance        <->   4. Test — eval-first gates
E. Merge/validate results     <--   5. Report — structured YAML
F. Bookkeep task file + learn           for orchestrator merge
G. Commit + push + persist

         COORDINATION (MCP-backed, optional)
         ====================================
         Claims — work-stealing queue
         Hive-mind — shared memory + consensus
         Model routing — sonnet/opus
         Progress — real-time tracking
         Learning — SONA trajectories
```

## Team Presets

| Preset | Agents | When to Use |
|--------|--------|-------------|
| **feature** | 1 lead + 2-3 implementers + 1 test agent | Multi-file feature implementation |
| **review** | 3-5 parallel reviewers | Security + performance + architecture audit |
| **debug** | 3 parallel debuggers (ACH) | Complex bug with multiple hypotheses |
| **fullstack** | frontend + backend + API + test | Cross-layer feature |
| **migration** | 2 implementers + 1 reviewer | Framework upgrade, API version bump |
| **research** | 3-5 Explore agents | Investigation, audit, data analysis |

## Capability Layers

| Layer | What | Requires | Default |
|-------|------|----------|---------|
| **Core** | Steps 0-G + Agent 1-5 | Claude Code Task tool | Always on |
| **Model routing** | Risk-based sonnet/opus selection | — | On |
| **Risk scoring** | Task classification by keywords | — | On |
| **Eval-first gates** | Baseline + regression detection | — | On |
| **Claims & rebalance** | Work-stealing queue | `mcp__claude-flow__claims_*` | Off (6+ agents) |
| **Progress tracking** | Real-time completion % | `mcp__claude-flow__progress_*` | Off (3+ batches) |
| **Session persistence** | Save/resume dispatches | `mcp__claude-flow__session_*` | Off (multi-hour) |
| **Hive-mind** | Shared memory + consensus | `mcp__claude-flow__hive-mind_*` | Off (cross-agent state) |
| **Learning loop** | Outcome recording for routing | `mcp__claude-flow__hooks_intelligence_*` | Off |

## Key Design Decisions

- **Orchestrator never implements** — it coordinates. Agents do all the work.
- **Never auto-push** — always requires your explicit approval.
- **Never auto-commit** — shows you the diff first.
- **3-way patch, not cp** — worktrees land on stale bases; naive copy overwrites recent changes.
- **Red team before code** — agents verify facts and challenge assumptions before writing anything.
- **Eval-first testing** — baseline snapshot before changes; abort on new regressions.
- **Saga compensation** — selective rollback of individual patches, not all-or-nothing.
- **Batch gates** — no batch N+1 until batch N is fully merged, tested, and conflict-free.
- **Sonnet default** — all agents use sonnet; opus reserved for complex architecture and security-critical review.

## Complementary Skills

| Skill | Role |
|-------|------|
| `parallel-feature-development` | File ownership strategies, interface contracts |
| `parallel-worktree-tasks` | Simpler variant without dependency graphs |
| `dispatching-parallel-agents` | Independence verification, when NOT to parallelize |
| `using-git-worktrees` | Worktree directory selection, project setup |
| `verification-before-completion` | Final quality gate before claiming done |
| `team-composition-patterns` | Preset team configurations for common scenarios |
| `task-coordination-strategies` | Decomposition strategies, workload rebalancing |
| `agentic-engineering` | Eval-first loops, 15-minute unit rule |
| `continuous-agent-loop` | Persistent loops for long-running dispatches |
| `swarm-orchestration` | Topology selection (mesh/hierarchical/adaptive) |

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- Git (for worktree isolation mode)
- A markdown task list file
- Optional: `claude-flow` MCP server for claims, progress, session, and learning features

## License

MIT
