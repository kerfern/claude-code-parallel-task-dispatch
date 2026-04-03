# parallel-task-dispatch

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) skill for orchestrating parallel task dispatch with git worktree isolation, dependency graphs, and file ownership.

Turn a task list into parallel agent work — each agent runs a full 6-step lifecycle (analyze, red-team, implement, test, report, bookkeep) while the orchestrator handles dependencies, file ownership, merge/reconcile, and commit.

## Features

- **Dependency-aware batching** — topological sort into parallel batches; respects `depends on` / `blocks` relationships
- **File ownership enforcement** — one writer per file per batch; overlap detection with automatic resolution
- **Git worktree isolation** — each agent works in its own worktree; 3-way patch merge back to main
- **Config mode** — for files outside git (e.g. `~/.claude/`); timestamped backups + validation
- **6-step agent lifecycle** — Analyze → Red Team → Implement → Test → Report (structured YAML)
- **Red team step** — agents challenge their own plans before coding; conflicts escalated to user
- **Pre-flight checks** — ensures clean tree before dispatch; prevents worktree base drift
- **Smart merge** — handles stale worktree bases with 3-way patch protocol; never uses `cp` or naive `git merge`
- **Agent type routing** — auto-selects agent type (TDD, security, refactor, etc.) based on task content
- **Batch gates** — mandatory validation between batches (conflicts resolved, tests pass, merges clean)

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

1. **Pre-flight** — ensures clean git tree, commits/pushes if needed (with your approval)
2. **Parse** — extracts tasks, dependencies, priorities, file targets
3. **Dependency graph** — topological sort into parallel batches
4. **File ownership** — assigns one writer per file; detects overlaps
5. **Execution plan** — shows you the plan; you approve before dispatch
6. **Dispatch** — agents run in parallel (git worktrees or config mode)
7. **Merge** — 3-way patch protocol; red team conflicts escalated to you
8. **Bookkeep** — updates task file with results, new findings, follow-ups
9. **Commit** — full test suite, then commit (push only with your approval)

## Architecture

```
ORCHESTRATOR (you / Claude)           AGENTS (per-task, isolated)
================================      ================================
0. Pre-flight — clean tree,           1. Analyze — read issue, verify
   commit + push                         depends/blocks, check facts
A. Parse task file                    2. Red team — challenge own plan,
B. Build dependency graph                verify files exist, check
C. Assign file ownership                 assumptions before coding
D. Dispatch parallel batches    -->   3. Implement — write code/config
E. Merge/validate results     <--    4. Test — run relevant tests
F. Bookkeep task file                 5. Report — structured YAML
G. Commit + push                         for orchestrator merge
```

## Execution Modes

| Mode | When | Isolation | Rollback |
|------|------|-----------|----------|
| **Git** | Target files in a git repo | `isolation: "worktree"` | `git tag` + `git reset` |
| **Config** | Files outside git (`~/.claude/`) | File ownership only | Timestamped backups |

Mode is auto-detected based on whether the target files are in a git repository.

## Key Design Decisions

- **Orchestrator never implements** — it coordinates. Agents do all the work.
- **Never auto-push** — always requires your explicit approval.
- **Never auto-commit** — shows you the diff first.
- **3-way patch, not cp** — worktrees land on stale bases; naive copy overwrites recent changes.
- **Red team before code** — agents verify facts and challenge assumptions before writing anything.
- **Batch gates** — no batch N+1 until batch N is fully merged, tested, and conflict-free.

## Complementary Skills

This skill works well with:

| Skill | Role |
|-------|------|
| `parallel-feature-development` | File ownership strategies, interface contracts |
| `parallel-worktree-tasks` | Simpler variant without dependency graphs |
| `dispatching-parallel-agents` | Independence verification, when NOT to parallelize |
| `using-git-worktrees` | Worktree directory selection, project setup |
| `verification-before-completion` | Final quality gate before claiming done |

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- Git (for worktree isolation mode)
- A markdown task list file

## License

MIT
