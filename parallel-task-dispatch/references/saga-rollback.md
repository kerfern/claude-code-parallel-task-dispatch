# Saga Compensation & Failure Analysis

## Saga Rollback Protocol

When a merge causes cascading failures (agent A's changes break agent B's):

1. **Identify the failing agent** via test suite errors + `git blame` on failing lines
2. **Selective rollback**: revert ONLY that agent's patch:
   `git apply --reverse /tmp/<failing_agent>.patch`
3. **Re-run tests** to confirm the remaining merges are clean
4. **Mark the failed task** as `status: failed` with reason
5. **If 2+ agents fail**: offer full rollback to `DISPATCH_BASE_SHA` tag
6. **Never leave main in a broken state** — either fix or rollback before proceeding

## Hypothesis-Driven Failure Analysis

For non-obvious test failures after merge:

1. Generate 2-3 hypotheses (e.g., "scope mismatch from agent A",
   "missing import from agent B's refactor", "pre-existing flaky test")
2. For each hypothesis, dispatch a debug agent:
   ```
   Agent(
     description="Debug hypothesis: {hypothesis}",
     subagent_type="team-debugger",
     model="sonnet",
     prompt="Investigate: {hypothesis}. Check {specific files}. Report evidence
             with file:line citations and confidence (high/medium/low).",
     run_in_background=true
   )
   ```
3. Compare evidence across hypotheses — highest-confidence wins
4. Apply targeted fix based on winning hypothesis

Only use for genuinely ambiguous failures. Most failures are obvious from the stack trace.
