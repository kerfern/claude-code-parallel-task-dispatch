# Session Persistence

Optional capability for multi-hour or multi-batch dispatches. Requires
`mcp__claude-flow__session_*` tools to be available.

## Resume Check (Step 0)

At pre-flight, before parsing the task file:

```
If mcp__claude-flow__session_* available:
  Check for saved dispatch session → offer to resume from last checkpoint
  If resuming: skip to the batch that was in progress, re-dispatch incomplete tasks
```

## Save Checkpoint (Step G)

After commit, save dispatch state for future resumption:

```
mcp__claude-flow__session_save(
  sessionId=dispatch_session_id,
  summary="Dispatch complete: N/M tasks, batch K of L"
)
```

This allows resuming an interrupted multi-batch dispatch in a future conversation.

## When to Enable

- Multi-batch dispatches expected to take >30 minutes
- Dispatches that span multiple conversation sessions
- Work that may be interrupted (laptop close, network drop)

Without session persistence, a new conversation starts the dispatch from scratch.
The skill works fine without it — this is a convenience enhancement.
