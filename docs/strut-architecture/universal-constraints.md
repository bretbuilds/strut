# STRUT Universal Constraints

Three layers. Each grounded differently.

---

## Layer 1: Mechanical enforcement

These are enforced by Claude Code infrastructure. The model operates within these constraints regardless of what its instructions say. Zero directive cost.

| Constraint | What it does | Source |
|-----------|-------------|--------|
| `tools:` in agent frontmatter | Agent cannot use tools not listed. Replaces prose prohibitions like "do not use Bash." | Anthropic Subagent Docs: frontmatter fields include `tools`. |
| `model:` in agent frontmatter | Sets which model runs the agent. | Anthropic Subagent Docs: frontmatter fields include `model`. |
| Fresh context per agent dispatch | Each agent starts with a fresh, isolated context containing its system prompt and dispatch message. It cannot see the parent's conversation history or other agents' reasoning. | Anthropic Subagent Docs: "Subagents run their own loops in isolated context." Anthropic Context Engineering: "clear separation of concerns — detailed search context remains isolated within sub-agents." |

**Implication for agent design:** Anything that CAN be enforced here SHOULD be enforced here. Every boundary constraint moved from prose to frontmatter is one fewer directive the model must self-regulate. Research on agentic instruction following specifically identifies tool specification constraints as one of the hardest constraint types for models to follow (AGENTIF). Moving tool restrictions to mechanical enforcement removes a constraint in the hardest category.

Frontmatter also supports `name:` and `description:` (required) and `memory:` (optional). Skills use only `name:` and `description:` in frontmatter; model recommendation goes in body text.

---

## Layer 2: Architecture

These are structural decisions about how the pipeline is organized. They shape agent behavior through the system's design rather than through directives to the model.

### Sequential orchestration

Orchestrators execute one step at a time: dispatch agent, check result, dispatch next agent. Only the current step's directives are active at any point.

**Source:** Anthropic Building Effective Agents: "Prompt chaining decomposes a task into a sequence of steps, where each LLM call processes the output of the previous one." STRUT orchestrators implement this pattern.

**Why this matters for directive cost:** Research on agentic instruction following finds that compliance degrades with both constraint count and instruction length (AGENTIF, Curse of Instructions). Sequential orchestration means the orchestrator never holds multiple complex requirements at once — it checks one result, then moves to the next step. This is an interpretation of the research, not a direct finding — neither paper tests sequential vs. simultaneous prompts. But the logic follows: if simultaneous constraints cause degradation, sequential structure reduces simultaneous load.

### Orchestrator-workers separation

Orchestrators dispatch and route. Workers do the actual task. This keeps orchestrator context lean (dispatch instructions + file checks) and gives each worker a focused role.

**Source:** Anthropic Building Effective Agents: "In the orchestrator-workers workflow, a central LLM dynamically breaks down tasks, delegates them to worker LLMs, and synthesizes their results." Anthropic Context Engineering: "the lead agent focuses on synthesizing and analyzing the results."

### File contracts

Agents communicate through structured output files in `.strut-pipeline/`. Every agent writes a result file containing at minimum `{skill, status}`. Orchestrators use status fields or file existence to route.

**Source:** Anthropic Context Engineering recommends that "detailed search context remains isolated within sub-agents" as a separation of concerns principle. File contracts are STRUT's implementation of this — agents write structured JSON, orchestrators read status fields, and no agent sees another agent's reasoning directly. The specific format (`{skill, status}` minimum, JSON files in `.strut-pipeline/`) is a STRUT design decision, not from documentation.

**Status vocabulary is agent-specific.** Each agent defines its own success/failure values (e.g., "passed," "classified," "drafted"). Orchestrators declare which values they check. This emerged from development — the working agents use different vocabularies and the orchestrators handle both.

---

## Layer 3: Directives

Everything in the agent body is a directive the model must process. This is the layer governed by research.

### The core principle

**Each directive in the agent body has a cost. Both the number of constraints and the length of instructions degrade compliance. Some constraint types are harder than others.**

This principle is established by three papers, each adding a dimension:

**AGENTIF (Qi et al., NeurIPS 2025)** is the primary reference. It tests instruction following specifically in agentic scenarios — real system prompts with tool specifications and complex constraints from 50 actual agentic applications. Key findings relevant to STRUT:

- Compliance degrades with both constraint count AND instruction length in agentic prompts. These are independent effects — long instructions with few constraints degrade, short instructions with many constraints degrade, and long instructions with many constraints degrade the most.
- Not all constraint types are equal. Tool specification constraints and condition constraints are harder for models to follow than simpler format or content constraints.
- Current models perform poorly on real-world agent instructions at typical complexity levels.

**Curse of Instructions (Harada et al., ICLR 2025)** establishes the exponential formula: success_all = success_individual^N. The rate of following ALL instructions drops exponentially with instruction count. This was tested on general tasks with discrete, independently verifiable directives.

**RECAST (ICLR 2026)** confirms the degradation pattern generalizes across models and constraint complexity levels, including the most recent model generation at time of publication.

**What the research does NOT establish:** A threshold number of directives or instruction length where compliance becomes unacceptable for any specific model version. Performance numbers are model-specific and shift across generations. The principle (more = worse, exponential form) survives model updates; the specific numbers don't.

### Constraint type costs

AGENTIF identifies that not all constraints are equally costly. This has direct implications for STRUT agent design:

**Tool specification constraints** — directives about which tools to use or not use — are in the hardest category. This strengthens the Layer 1 argument: tool restrictions enforced mechanically via frontmatter remove a constraint in the most expensive category.

**Condition constraints** — directives with "if [condition], then [action]" structure — are harder than simple format or content constraints. This is directly relevant to anti-rationalization patterns. "Thinking X? STOP." is a condition constraint — it asks the model to monitor its own reasoning state and act conditionally. Each anti-rationalization pattern is in the more expensive constraint category.

This doesn't mean anti-rationalization patterns are wrong to use. It means each one is more costly than a simpler directive, and the "add only when you observe the failure" method is even more important — you want to be sure the pattern is preventing a real problem before paying the higher cost.

### The method

**Start minimal. Add based on observed failures.**

Source: Anthropic Context Engineering: "start by testing a minimal prompt with the best model available to see how it performs on your task, and then add clear instructions and examples to improve performance based on failure modes found during initial testing." And: "good context engineering means finding the smallest possible set of high-signal tokens that maximize the likelihood of some desired outcome."

The AGENTIF finding that both length and constraint count independently degrade compliance reinforces this — every directive you add increases cost on both dimensions (it's one more constraint AND it makes the instruction longer).

In practice for STRUT:

1. Write the agent with only what it needs: role, inputs, output schema, and core task instructions.
2. Test it.
3. When you observe a specific failure (agent does something it shouldn't, produces wrong output format, wanders off task), add one targeted directive to address that failure.
4. That directive is now justified by an observed failure and carries a known cost.
5. Before adding a prose directive, check whether it can be moved to Layer 1 (frontmatter) or Layer 2 (architecture) instead. This is especially important for tool restrictions (hardest constraint category) and condition constraints (expensive category).

### Writing effective directives (observed techniques)

When the method calls for adding a directive, these techniques apply across the pipeline. They have no documentation or research backing — they are observed patterns from STRUT development that address failure modes likely to recur in any agent or skill in the architecture.

**Condition constraints: use "Thinking X? STOP." format.** Polite phrasing ("Please don't do X") was less effective than direct interception of the model's reasoning. This format was observed to work where polite phrasing failed, across multiple agents. No minimum count is prescribed — add these only when you observe the model rationalizing past a constraint. AGENTIF identifies condition constraints as one of the harder types, so each one carries above-average directive cost.

**Explore agent: ban explicitly in every agent.** Opus launches Claude Code's Explore agent between pipeline steps when not explicitly banned, consuming significant tokens. This applies to any agent in the pipeline, not just Read Truth. The ban cannot be moved to frontmatter because Explore is a model behavior, not a tool in the `tools:` list.

**Failure behavior: "write file, stop" in every worker agent.** Agents write their result file with a failure status and stop. They don't retry, suggest workarounds, or ask how to proceed. The instruction "ask how to proceed" was observed to produce bypass options where the model finds ways around the failure. Retry logic lives in orchestrators only. This applies to every worker agent in the pipeline.

---

## Orchestrator Skills (how STRUT skills differ from agents)

STRUT uses skills as orchestrators (dispatch + route) and agents as workers (isolated tasks). Skills and agents operate under different constraints because Claude Code treats them differently.

### What's documented differently

**Skills share the parent's context. Agents get isolated context.**

Source: Claude Code Skills docs: skills run inline in the parent's context by default. Claude Code Subagent docs: "Each subagent runs in its own context window." Skills also support `context: fork` to run in isolated context, but STRUT orchestrators intentionally share context — that's how they dispatch agents and check file results across steps.

This is the most important difference. An agent's directives compete only with each other. A skill's directives compete with conversation history, CLAUDE.md, rules files, and everything else in the session.

**Skills have a documented line limit. Agents don't.**

Source: Anthropic Skill Best Practices: "Keep SKILL.md body under 500 lines for optimal performance." Rationale: "The context window is a public good. Your Skill shares the context window with everything else Claude needs to know."

This is the only documented length threshold in all of STRUT's constraints. It applies to skills specifically because of shared context. No equivalent limit exists for agent files. The AGENTIF finding that instruction length independently degrades compliance reinforces why this limit matters — skills sharing context are inherently working with longer effective instruction length.

**Skills have fewer mechanical enforcement options.**

Source: Claude Code Skills docs and Subagent docs, comparing frontmatter fields.

| Enforcement | Agents | Skills |
|------------|--------|--------|
| Model selection | `model:` in frontmatter | Not available — inherits session model |
| Tool restriction | `tools:` / `disallowedTools:` | `allowed-tools:` (CLI only) |
| Context isolation | Automatic (fresh per dispatch) | Opt-in via `context: fork` (not used by STRUT orchestrators) |
| Effort level | `effort:` | `effort:` |

Skills cannot set their own model. STRUT orchestrators inherit the session model (typically Sonnet). This means model selection for orchestrators is a session-level decision, not a per-skill mechanical constraint.

Skills CAN restrict tools via `allowed-tools:` in CLI, which provides mechanical enforcement similar to agents' `tools:` field. STRUT orchestrators need Task + Read + Bash + Write to do their job, so restriction isn't practically useful for them — but it's available.

### How the three layers apply to skills

**Layer 1 (Mechanical):** Limited. `allowed-tools:` is available but not practically useful for orchestrators. `model:` is not available. Context isolation is not used (orchestrators share context by design). The main Layer 1 advantage for agents — moving boundary constraints to frontmatter — is mostly unavailable for skills.

**Layer 2 (Architecture):** Applies fully. Sequential orchestration, orchestrator-workers separation, and file contracts are all architectural patterns that don't depend on whether the orchestrator is a skill or an agent.

**Layer 3 (Directives):** Applies, with higher stakes. The AGENTIF finding that both constraint count and instruction length degrade compliance applies to skill bodies the same as agent bodies. But because skills share context, their effective instruction length is longer — the model is processing the skill's directives alongside everything else in the session. The Anthropic context engineering guidance — "smallest possible set of high-signal tokens" — is more acute for skills than for agents.

The "start minimal, add based on observed failures" method applies identically. The 500-line documented limit provides a ceiling that agents don't have.

### What this means for STRUT orchestrator skills

STRUT orchestrators are thin by design — they dispatch agents and check file results. Their directive count is naturally low: a sequence of "dispatch X, check Y, if passed continue, if failed stop" steps. This keeps them well under 500 lines and keeps simultaneous directive count minimal (each step is one check).

Operational patterns from Read Truth (anti-rationalization, Explore ban, failure behavior) apply to skills the same as agents — they're directives in the body regardless of which mechanism runs them. The same "add only when you observe a failure" method applies.

---

## Summary

| Layer | What | Grounding | Cost |
|-------|------|-----------|------|
| Mechanical | frontmatter `tools:`, `model:`, context isolation | Anthropic documentation (direct) | Zero |
| Mechanical (skills) | `allowed-tools:` (CLI), `effort:` | Anthropic documentation (direct) | Zero |
| Architecture | sequential orchestration, orchestrator-workers, file contracts | Anthropic documentation (patterns); STRUT design (implementation) | Zero per-directive; structural |
| Directives (agents) | everything in the agent body | AGENTIF, Curse of Instructions, RECAST (principle); Anthropic context engineering (method) | Each directive compounds; constraint type affects cost |
| Directives (skills) | everything in the skill body | Same principle; shared context amplifies cost; 500-line documented limit | Each directive compounds + context competition |

**One decision rule:** If a constraint can be enforced mechanically (Layer 1), don't enforce it with a directive (Layer 3). If a constraint can be handled by architecture (Layer 2), don't put it in the body (Layer 3). For skills specifically: keep them thinner than agents because shared context means higher directive cost.

---

## References

### Research papers

**AGENTIF: Benchmarking Instruction Following of Large Language Models in Agentic Scenarios**
Qi et al. NeurIPS 2025 Datasets and Benchmarks Track (Spotlight).
Tests instruction following in agentic scenarios specifically. 707 instructions from 50 real-world agentic applications. Finds compliance degrades with both constraint count and instruction length. Identifies tool specification and condition constraints as hardest types.
https://arxiv.org/abs/2505.16944

**Curse of Instructions: Large Language Models Cannot Follow Multiple Instructions at Once**
Harada et al. ICLR 2025.
Establishes the exponential formula: success_all = success_individual^N. Tests discrete, independently verifiable directives on general tasks (1-10 instructions).
https://openreview.net/forum?id=R6q67CDBCH

**RECAST: Expanding the Boundaries of LLMs' Complex Instruction Following with Multi-Constraint Data**
ICLR 2026.
Confirms degradation pattern across models and constraint complexity levels. Even best-performing models show consistent degradation from simple to complex multi-constraint scenarios.
https://arxiv.org/abs/2505.19030

### Anthropic documentation

**Skill Authoring Best Practices** — SKILL.md authoring guidance including the 500-line recommendation, progressive disclosure, and conciseness principles.
https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices

**Agent Skills Overview** — Architecture, loading levels, and how skills work.
https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview

**Create Custom Subagents** — Subagent frontmatter fields, context isolation, tool restrictions, and model selection.
https://code.claude.com/docs/en/sub-agents

**Extend Claude with Skills** — Skill frontmatter fields, content lifecycle, and invocation control.
https://code.claude.com/docs/en/skills

**Effective Context Engineering for AI Agents** — Context as finite resource, "smallest possible set of high-signal tokens," start minimal and add based on failures.
https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents

**Building Effective Agents** — Prompt chaining, orchestrator-workers, and other agent patterns. "Add complexity only when it demonstrably improves outcomes."
https://www.anthropic.com/research/building-effective-agents