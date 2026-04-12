# parallel-task-dispatch

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) skill for orchestrating parallel task dispatch with dependency graphs, file ownership, risk scoring, and merge coordination.

Turn a task list into parallel agent work — each agent runs a full 6-step lifecycle (analyze, red-team, implement, test, report) while the orchestrator handles batching, merge, saga rollback, and commit.

## Features

- **Dependency-aware batching** — topological sort with `depends on` / `blocks`
- **File ownership** — one writer per file per batch; overlap → serial batches
- **Risk scoring + model routing** — keyword heuristic → sonnet default, opus for critical review
- **6-step agent lifecycle** — Analyze, Red Team, Implement, Test (eval-first), Report (YAML)
- **3 execution modes** — file-ownership-parallel (default), serial-batches, worktree-parallel
- **Saga compensation** — selective rollback of individual agent patches
- **Team presets** — feature, review, debug, fullstack, migration, research
- **MCP-enhanced** (optional) — claims/work-stealing, progress tracking, session persistence, shared memory

See `parallel-task-dispatch/SKILL.md` for full architecture, step-by-step orchestration, and agent type routing.

## Installation

### Quick Install

```bash
git clone https://github.com/kerfern/claude-code-parallel-task-dispatch.git /tmp/ptd
bash /tmp/ptd/install.sh
```

### Manual Install

```bash
mkdir -p ~/.claude/skills/parallel-task-dispatch ~/.claude/commands

curl -o ~/.claude/skills/parallel-task-dispatch/SKILL.md \
  https://raw.githubusercontent.com/kerfern/claude-code-parallel-task-dispatch/main/parallel-task-dispatch/SKILL.md

curl -o ~/.claude/commands/update-parallel-task-dispatch.md \
  https://raw.githubusercontent.com/kerfern/claude-code-parallel-task-dispatch/main/commands/update-parallel-task-dispatch.md
```

### Verify

```
/parallel-task-dispatch docs/tasks.md
```

### Update

Run `/update-parallel-task-dispatch` inside any Claude Code session.

## Usage

```
/parallel-task-dispatch path/to/task-list.md
/parallel-task-dispatch path/to/task-list.md --dry-run
/parallel-task-dispatch path/to/task-list.md --preset=feature
/parallel-task-dispatch path/to/task-list.md --worktree
```

### Task List Format

Any markdown task list. Dependencies and priority extracted automatically:

```markdown
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

1. **Pre-flight** — clean git tree, save rollback SHA
2. **Parse + plan** — extract tasks, risk-score, build dependency graph, assign file ownership
3. **Dispatch** — agents run in parallel per batch (worktrees or file-ownership isolation)
4. **Merge + validate** — batch gate: completeness grep, ownership check, full test suite
5. **Commit** — bookkeep task file, commit (push only with your approval)

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- Git (for worktree isolation mode)
- A markdown task list file
- Optional: `claude-flow` MCP server for claims, progress, session, and learning features

## License

MIT
