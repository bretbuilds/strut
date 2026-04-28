---
globs: .claude/skills/**, .claude/agents/**, .claude/scripts/**
---

# Pipeline Rules

<!-- Pipeline internals: agent and skill authoring constraints, file contracts, execution behavior. Scoped to pipeline paths only — does not load during ordinary feature work. -->

## Agent Constraints

1. Ban the Explore agent explicitly in every agent body. Opus launches Explore between pipeline steps when not explicitly banned, consuming significant tokens. The ban cannot be moved to frontmatter — Explore is a model behavior, not a tool.
2. On failure: write the result file with a failure status and STOP. Do not retry, do not suggest workarounds, do not ask how to proceed. Retry logic lives in orchestrators only.
3. Start minimal. Add directives based on observed failures only. Before adding a directive, check whether frontmatter (`tools:`, `model:`) or architecture (file contracts, sequential orchestration) can enforce it instead — directives are the most expensive layer.
4. Isolated context per dispatch. An agent receives only its declared inputs and writes one result file. It does not read other agents' reasoning.

## Skill (Orchestrator) Constraints

5. Skills orchestrate, agents do work. If an orchestrator is performing reasoning, implementation, or review work, it should be an agent. Orchestrators dispatch and route — nothing more.
6. Keep skill bodies thin. Anthropic's skill-authoring guidance recommends keeping SKILL.md bodies under 500 lines for optimal performance with shared context.
7. Skills can nest; agents cannot. Sub-orchestrators exist as skills because Claude Code does not allow agents to spawn other agents.

## File Contracts

8. Every agent writes exactly one result file to `.pipeline/`. The file path is declared in the agent's inventory and does not change.
9. Orchestrators route on the `status` field alone. They never read agent reasoning or content fields.
10. Information crosses agent boundaries only through `.pipeline/` file contracts. No passing data through conversation context between agents.
11. `rm -f` the target file before writing. Stale files from previous runs must never be mistaken for current results.

## Pipeline Execution

12. Skills are project-agnostic. Project-specific details come from input files and rules, not from hardcoded references in skill bodies.
13. If a pipeline skill needed for the next step does not exist: STOP. Report which skill is missing and what the next step would be. Do NOT improvise the missing skill's job inline.
14. Resume from file state: every gate writes `process-change-state.json`. Every resume reads it. The pipeline survives hours or days of human pause.

Full architecture: `docs/strut-architecture/core-path-architecture.md`