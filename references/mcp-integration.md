# MCP Integration Reference

Optional MCP tools that enhance dispatch when available. The skill works without them —
they add coordination, persistence, and learning capabilities. Referenced from `SKILL.md`
under "MCP Integration Reference".

| Capability | Tools | When |
|-----------|-------|------|
| **Claims / work stealing** | `claims_claim`, `claims_release`, `claims_steal`, `claims_rebalance`, `claims_load` | 6+ agents, uneven task sizes |
| **Progress tracking** | `progress_check`, `progress_summary` | 3+ batches, user wants visibility |
| **Session persistence** | `session_save`, `session_restore` | Multi-hour dispatches, resumable work |
| **Shared memory** | `hive-mind_init`, `hive-mind_memory`, `hive-mind_broadcast` | Cross-agent state (shared config, feature flags) |
| **Model routing feedback** | `hooks_model-route`, `hooks_model-outcome`, `hooks_model-stats` | Continuous model selection improvement |
| **Learning trajectories** | `hooks_intelligence_trajectory-start/step/end` | Pattern extraction for future dispatches |
| **Diff risk analysis** | `analyze_diff`, `analyze_diff-risk`, `analyze_diff-reviewers` | Auto-reviewer suggestion post-merge |
| **Consensus** | `coordination_consensus`, `hive-mind_consensus` | Multi-agent decisions (rare — e.g., conflicting approaches) |
| **Topology** | `coordination_topology`, `swarm_init` | 10+ agents, complex dependency graphs |
