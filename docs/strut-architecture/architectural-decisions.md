# Decision Rationale

This document maps each load-bearing architectural decision in STRUT to the evidence that informed it. It covers decisions most likely to be questioned or revisited — structural choices about pipeline shape, not tuning choices about specific parameter values.

## How to use this document

Entries are organized by architectural concern rather than pipeline phase. Questions about the architecture tend to arrive as conceptual ("why is the review chain fail-fast?") rather than phase-specific ("why does review-criteria-eval exist?"), and many decisions are cross-cutting — the modifier system, the two-layer orchestration model, and the source-of-truth framing shape the whole pipeline rather than any single phase. Where an entry corresponds to a specific phase or component in `docs/core-path-architecture.md`, the component is named in the entry.

Citations are tier-labeled so the strength of support is visible at a glance:

- **[R]** — Peer-reviewed research or industry reports with stated methodology. Strongest evidence.
- **[I]** — Industry reports without full methodology transparency. Citable but less defensible under scrutiny.
- **[P]** — Practitioner conventions and observations.
- **[A]** — Anthropic documentation.
- **[D]** — Our judgment. Stated explicitly so it can be owned as such.

Decisions supported by multiple **[R]**-tier sources are well-grounded. Decisions marked **[D]** are judgment calls — valid, but held for the reasons stated rather than the strength of external evidence.

URLs are included only for sources with confirmed stable public URLs. Other sources are cited by name and year; readers who want to verify can search by title.

"Platform coupling" notes indicate which decisions transfer to any LLM platform versus which depend on Claude Code specifically.

This doc is organized by concern. For a per-component index of sources organized by architecture section, see `research-index.md`.

---

## Foundational principles

### Spec-first development

Nothing enters implementation without an approved spec. STRUT's interpretation: grounding intent upstream reduces the surface area where the implementation can diverge from what the human actually wanted.

- **[R]** METR RCT (2025): Developers believed AI made them 24% faster but were 19% slower. Root cause was prompting AI before clarifying intent.
- **[I]** GitHub Spec Kit: Separation of "what and why" from "how" as the organizing principle for spec-driven development.

Platform coupling: None.

### TDD enforcement (tests before implementation)

`impl-write-tests` runs before `impl-write-code`. This is structural, not a suggestion — `impl-write-code` takes tests as input and has no path to satisfy the spec except by passing them.

TDD is more critical with AI than without it because AI amplifies whatever practice the team is using. Tests encode human intent in executable form; code is one possible implementation of that intent. Without tests, every generation is unverified; with tests, each generation is mechanically checked against the contract.

- **[R]** DORA Report (2025): TDD "more critical than ever" with AI-assisted development.
- **[R]** CodeRabbit (2025): AI code has 1.7× more issues per PR (10.83 vs. 6.45) across 470 PRs analyzed.
- **[R]** Sol-Ver (Lin et al., 2025): Self-play between solver (code generator) and verifier (test generator) yields 19.63% improvement — the test-generator drives code-generator quality.
- **[R]** AlphaCode (Li et al., 2022, Science): Generate-and-filter paradigm. One million candidate programs per problem, 99% filtered through test execution. The test suite is the selection mechanism.

Platform coupling: None.

### Tests are the permanent asset, code is disposable

When tests exist to verify correctness, any implementation can be regenerated. This reframes the relationship: code is the variable, tests are the constant.

- **[I]** Darwin Gödel Machine (Sakana AI, 2025): Less-performant ancestor agents sometimes produced breakthrough descendants. Attachment to existing code is counterproductive.
- **[R]** MSR (2026): Agent-generated code shows more churn than human-authored code across ~110,000 open-source PRs.
- **[R]** GitClear (2024): 8× increase in duplicated code blocks 2020–2024 across 211M lines analyzed; copy-paste surpassed refactoring for the first time.
- **[R]** AlphaEvolve (Novikov et al., 2025): Continuous evolutionary optimization of codebases with automated test suites as the fitness function.

Platform coupling: None.

### Two modifiers (trust + decompose) instead of tiers

Every pipelined change has the same structural shape. Two binary modifiers adjust ceremony: trust (is this change trust-sensitive?) and decompose (is this change structurally complex?). An earlier three-tier system collapsed two independent concerns — risk and complexity — into a single ordinal scale; modifiers decompose them cleanly.

- **[D]** Simplified from an earlier tier system during design. Modifiers composed independently rather than stacked on a single dimension, which matches observed work: a trivial UI change touching auth is high-risk low-complexity; a feature crossing three boundaries without trust sensitivity is low-risk high-complexity.

Platform coupling: None.

### Trust modifier triggered by risk signals from the scan

Trust ON activates on any of: auth, RLS, schema migrations, security boundaries, immutability, multi-tenant isolation. Triggers are hard — if any signal fires, trust is ON regardless of apparent simplicity. The decision comes from the scan, not from session-level Claude.

AI-generated code is disproportionately risky in trust-sensitive domains. The general defect-rate premium is compounded when the code touches trust boundaries, making explicit identification essential rather than optional.

- **[I]** Apiiro (2025): 322% more privilege escalation paths in AI code vs. human-written.
- **[I]** Veracode (2025): 45% of AI-generated code introduces OWASP Top 10 vulnerabilities.
- **[R]** CodeRabbit (2025): Security vulnerabilities 1.5–2× more frequent in AI code.

Platform coupling: None.

### Decompose modifier triggered by architectural boundary crossings

Decompose ON activates when the change crosses 2+ architectural boundaries (UI / server / database). This produces a task breakdown of up to 5 tasks, each independently testable.

LLM performance degrades with instruction and scope count. Keeping each task within effective range — one boundary, one concern — produces better output per task than one dispatch that spans the full change.

- **[R]** Curse of Instructions (Harada et al., ICLR 2025): Exponential degradation formula — success_all = success_individual^N. https://openreview.net/forum?id=R6q67CDBCH
- **[R]** AGENTIF (Qi et al., NeurIPS 2025): Compliance degrades with both constraint count and instruction length, with some constraint types above-average cost. https://arxiv.org/abs/2505.16944
- **[R]** CooperBench (2025): Isolated single-task agents outperform multi-task approaches (roughly 50% single vs. 25% collaborative).

Platform coupling: None.

---

## Orchestration architecture

### Two-layer model (skills orchestrate, agents do work)

Skills dispatch agents and check file results. Agents perform the actual work (spec writing, test writing, implementation, review). Skills never produce reasoning output; agents never dispatch other agents.

This pattern maps directly to Anthropic's orchestrator-workers pattern. The division keeps skill bodies thin (a sequence of dispatch-check-dispatch steps) while letting agent bodies carry full task context.

- **[A]** Anthropic Building Effective Agents (2025): "In the orchestrator-workers workflow, a central LLM dynamically breaks down tasks, delegates them to worker LLMs, and synthesizes their results." https://www.anthropic.com/research/building-effective-agents
- **[A]** Anthropic Context Engineering (2025): "The lead agent focuses on synthesizing and analyzing the results." https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents

Platform coupling: The orchestrator-workers pattern is portable. The specific skill/agent distinction and frontmatter mechanics are Claude Code-specific.

### Isolated context per worker agent

Each agent runs in its own context window, receiving only its declared inputs and producing one result file. No agent sees another agent's reasoning.

STRUT's interpretation of the isolation research: reviewers with shared context risk correlated assessments, where one reviewer's framing biases the next. Enforced isolation at the framework level makes this structurally impossible rather than relying on reviewer discipline.

- **[A]** Anthropic Subagent Docs: "Each subagent runs in its own context window." https://code.claude.com/docs/en/sub-agents
- **[A]** Anthropic Context Engineering: "Clear separation of concerns — detailed search context remains isolated within sub-agents."
- **[R]** CooperBench (2025): 25% success rate when two agents collaborate vs. ~50% solo, establishing that isolated single-task design outperforms collaborative multi-task.

Platform coupling: The mechanism (frontmatter + automatic context isolation) is Claude Code-specific. The principle — isolated single-task scope produces better output than multi-task — generalizes.

### Sub-orchestrator hierarchy

Phase-level sub-orchestrators (run-spec-refinement, run-implementation, run-review-chain, run-build-check, run-update-truth) each get fresh context within the shared session. The top-level orchestrator (run-strut) never reads individual agent results, only sub-orchestrator status.

STRUT's interpretation: a single flat orchestrator running a decompose-ON pipeline would accumulate 20–30 dispatch cycles of context. Sub-orchestrators partition that load at phase boundaries, keeping any single orchestrator within effective instruction-following range.

- **[R]** AGENTIF (Qi et al., NeurIPS 2025): Instruction length independently degrades compliance in agentic prompts.
- **[A]** Anthropic Context Engineering (2025): "The lead agent focuses on synthesizing and analyzing the results" while detail remains in sub-agents.

Platform coupling: The mechanism (session-inherited context for nested skills) is Claude Code-specific. The principle (partition work to control effective context length) is general.

### File contracts as inter-agent communication

Agents communicate through structured JSON files in `.strut-pipeline/`. Every result file contains at minimum `{skill, status}`. Orchestrators route on status; they never read content fields from agent outputs.

File contracts make the orchestrator's routing logic auditable and deterministic — no LLM reasoning is involved in deciding "did this step pass?" beyond reading a string field. This also prevents orchestrator context bloat from accumulating full agent outputs.

- **[A]** Anthropic Context Engineering (2025): Recommends "detailed search context remains isolated within sub-agents" as a separation-of-concerns principle.
- **[D]** The specific format (`{skill, status}` minimum, JSON files in `.strut-pipeline/`) is our design choice. No external source prescribes this format.

Platform coupling: None. Any platform with a filesystem works.

### Mechanical enforcement over directive instruction

If a constraint can be enforced via frontmatter (`tools:`, `model:`) or architecture (file contracts, sequential dispatch), enforce it there. Avoid re-stating the constraint as a directive in the agent body.

Tool specification constraints are identified as one of the hardest constraint types for models to follow. Moving tool restrictions from prose to frontmatter removes a constraint in the most expensive category entirely.

- **[R]** AGENTIF (Qi et al., NeurIPS 2025): Tool specification constraints and condition constraints are harder than simple format or content constraints.
- **[A]** Anthropic Subagent Docs: Frontmatter `tools:` field restricts available tools regardless of instructions.

Platform coupling: Frontmatter is Claude Code-specific. The principle (prefer mechanical enforcement to directive enforcement) applies to any platform with an analogous mechanism.

### Start minimal; add directives based on observed failures

New agents ship with only what they need: role, inputs, output schema, core task instructions. Directives are added reactively — observe a specific failure, add one targeted directive, verify the failure stops.

Every added directive increases cost on two dimensions independently: one more constraint, and a longer instruction. Speculative directives ("we might need this") inflate cost without addressing any observed problem.

- **[A]** Anthropic Context Engineering (2025): "Start by testing a minimal prompt with the best model available to see how it performs on your task, and then add clear instructions and examples to improve performance based on failure modes found during initial testing."
- **[A]** Anthropic Building Effective Agents (2025): "Add complexity only when it demonstrably improves outcomes."
- **[R]** AGENTIF (Qi et al., NeurIPS 2025): Count and length independently degrade compliance.
- **[R]** RECAST (ICLR 2026): Degradation pattern confirmed across models and constraint complexity levels. https://arxiv.org/abs/2505.19030

Platform coupling: None.

---

## Review and gating

### Fail-fast review chain

The review chain stops at the first failure. On retry after revision, the full chain re-runs from the first reviewer — the revised diff may have introduced new issues the earlier reviewers should re-check.

Accumulating failures across all reviewers before returning produces larger remediation cycles with conflated feedback. Failing fast gives the implementer focused feedback on one issue at a time.

- **[A]** Anthropic Context Engineering: "Smallest possible set of high-signal tokens." Small focused feedback is higher-signal than a list of accumulated concerns.
- **[R]** CodeRabbit (2025): Senior engineers spend 3.6× longer reviewing AI code (4.3 min per suggestion vs. 1.2 min for human code). Efficient review requires focusing attention on confirmed issues.

Platform coupling: None.

### Shared retry budget across the chain

Retries are counted across the full review chain, not per reviewer. Exhausting the budget escalates to human rather than continuing to loop.

Unbounded retry loops consume tokens without converging. A shared kill-criterion prevents the pipeline from spending arbitrary amounts of effort on a change that isn't trending toward pass.

- **[P]** Addy Osmani: Kill criteria after 3+ iterations on the same error.
- **[R]** AGENTIF: Retry logic as directive instruction is complex conditional behavior — cheaper to handle in orchestrators than as in-agent directives.

Platform coupling: None.

### Two human gates (spec approval, PR review)

The pipeline pauses at two points: after spec refinement, and after PR opening. Human judgment is explicitly required; the pipeline does not auto-approve either.

Review is the bottleneck in AI-assisted workflows. Without human gates, PR volume exceeds review capacity and gates become rubber-stamp approvals. Placing gates at high-leverage points (spec before implementation, PR before merge) concentrates review effort where it converts into the most protection.

- **[R]** Faros AI (2025): Individuals complete 21% more tasks but PR review time increases 91%. Company-wide throughput 0%. Review is the bottleneck.
- **[I]** Cognition (Devin Review): PR volume exceeds review capacity → rubber-stamp approvals.
- **[I]** ACM Queue (2025): Developer role shifts to navigator/reviewer. Review IS the work, not overhead on the work.

Platform coupling: None.

### "Override, not approve" framing at the spec gate

The spec approval gate asks the human to make the spec theirs — to edit, refine, or reject — rather than to verify the AI's work. This shifts the human's role from checker to author.

STRUT's interpretation: "approve" language invites superficial verification, which is the observed failure mode at human gates (rubber-stamping). "Override" language requires engagement. The framing shift is ours; the underlying observation is the METR finding below.

- **[D]** Framing choice based on the METR finding about the perception-reality gap.
- **[R]** METR RCT (2025): The 39-percentage-point perception gap came from humans not doing enough work upfront.

Platform coupling: None.

### Automated review chain before human review

Scope, criteria, and (trust ON) security reviews run before the human sees anything. The human reviews pre-filtered output, not the raw diff.

Pre-filtering converts human review from "verify correctness at every level" to "verify intent at the conceptual level." The automated chain handles mechanical checks the human would otherwise spend time on; the human spends saved time on judgment calls the chain can't make.

- **[R]** CodeRabbit (2025): 3.6× longer review time for AI code. Pre-filtering by automated chain reduces what humans must verify manually.
- **[R]** Faros AI (2025): 91% increase in review time consumed all individual productivity gains. Reducing review load is the highest-leverage intervention.

Platform coupling: None.

---

## Security and trust

### MUST NEVER constraints as negative tests

When trust is ON, intent statements include a `must_never` array. Each entry becomes a criterion with negative type, which `impl-write-tests` translates into a test that verifies the violation is rejected rather than silently ignored.

Trust boundaries must be explicitly named to be reliably enforced. Encoding "must never" as an executable test prevents drift — if a future change introduces the violation, the test fails.

- **[I]** Apiiro (2025): Trust boundaries require explicit adversarial consideration; 322% more privilege escalation paths in AI code.
- **[R]** METR RCT (2025): Intent clarified from documented sources outperforms human recall under time pressure.

Platform coupling: None.

### Security review as a separate chain step (trust ON)

Under trust ON, review-scope and review-criteria-eval are followed by a review-security step. It runs on a higher-capability model and uses trust-sensitive rule content as its evaluation frame.

AI-generated code shows above-baseline frequency of privilege escalation, OWASP violations, and security vulnerabilities. These are not general correctness issues a scope or criteria reviewer would catch; they require domain-specific security reasoning.

- **[I]** Apiiro (2025): 322% more privilege escalation paths.
- **[I]** Veracode (2025): 45% OWASP Top 10 violation rate.
- **[R]** CodeRabbit (2025): Security vulnerabilities 1.5–2× more frequent in AI code.

Platform coupling: Specific model assignment (Opus for review-security) is Claude-specific. The principle — invest higher-capability reasoning in trust-sensitive judgment — is general.

---

## Knowledge capture and self-improvement

### The self-improving rules cycle

The scan reads `.claude/rules/*` for trust-sensitive definitions. When it detects a risk signal without a matching rule, it outputs a `rules_gaps` entry. After merge, `update-capture` proposes rule text for the gap. The human reviews and applies. The next scan reads the new rule — the blind spot closes.

Substrate quality compounds over time. Each change is both a delivery event (the code change) and a potential knowledge-capture event (a rule that prevents a class of future problems).

- **[R]** DORA Report (2025): Continuous improvement through automated feedback loops as a foundation for engineering effectiveness.

Platform coupling: None.

### Capture-decisions proposes; humans apply

`update-capture` never writes to `.claude/rules/*` directly. It produces proposals in `knowledge-proposals.json` that the human reviews and applies.

Substrate changes govern all future pipeline runs. An agent writing directly to the substrate could introduce errors that compound across every subsequent run, or make changes the human disagrees with but can't easily detect. Proposals-with-approval keeps the human in the loop at the leverage point.

- **[R]** Faros AI (2025): Human remains the control point for substrate changes. Automation below, judgment above.

Platform coupling: None.

### Process-friction trigger

`update-capture` flags pipeline friction regardless of whether the change was trust-sensitive — extra spec cycle iterations, review chain retries, build-check cleanup attempts. Friction is early warning that something in the substrate (rules, patterns, directives) can be improved.

A change that passes but required three review rounds tells you something even if the final merge is clean. Capturing friction signals lets the substrate improve before friction becomes failure.

- **[R]** DORA Report (2025): Without strong testing and automation, increased change volume produces instability. Friction is early warning.

Platform coupling: None.

---

## Knowledge substrate

### Source of truth: codebase + tests + knowledge substrate

The authoritative state of the system is the working code, the test suite, and the knowledge substrate (rules, decisions log, system map). Specs are transient — consumed on merge, archived in `.strut-specs/` for historical reference.

An earlier design treated the spec as the source of truth, with code as its output. This inverts once the code exists: the code is what runs, the tests are what verify it, and specs are the instruction that produced this particular diff. After merge, the spec's job is done.

- **[D]** Design principle derived during architecture development. Grounding is structural: code and tests are what ship; specs are ephemeral change proposals.
- **[I]** Darwin Gödel Machine (Sakana AI, 2025): Attachment to existing code is counterproductive — the test suite is the invariant, implementations are the variable.

Platform coupling: None.

### Repo impact scan as grounding mechanism

Before any planning happens, the scan reads the actual codebase to produce structured evidence about what the change touches, what risk signals fire, and what architectural boundaries are involved.

Planning from assumptions produces misaligned specs. Planning from scan evidence grounds the spec in real file paths, existing patterns, and actual dependencies — the implementation_notes reference code that exists rather than code the AI imagined.

- **[R]** METR RCT (2025): Grounding from documented sources outperforms recall under time pressure.
- **[D]** Design decision: the scan runs before planning specifically so that downstream agents operate on evidence rather than assumption.

Platform coupling: None.

### docs/user-context/ as optional enrichment

`spec-derive-intent` reads `docs/user-context/` before spec writing for business context that isn't visible from the code alone: product decisions, user expectations, domain vocabulary. The pipeline works without this folder; it works better with it.

Scan evidence tells the pipeline what the code does. It doesn't tell the pipeline what the product is trying to accomplish, what the user expects, or what domain words mean. Teams that populate this folder see thicker specs with more accurate intent statements. Teams that skip it see thinner specs that the human has to enrich at the spec approval gate.

- **[D]** Design choice to make context enrichment optional rather than required, recognizing that requiring it would block adoption.

Platform coupling: None.

---

## A note on what this document doesn't cover

Several decisions in STRUT were tuning choices rather than structural ones: specific iteration counts (5 spec cycles, 3 retry attempts), specific criterion count ranges (3–7), specific model assignments to specific agents, specific directive wording patterns. These are documented in `docs/core-path-architecture.md` but not here, because they are:

- Empirically tunable — observable failure modes will indicate whether the specific number is right for your adoption
- Current-model dependent — behavior that informs these choices will shift with model generations
- Not architecturally load-bearing — changing the number doesn't change the shape of the pipeline

If you want the full list of tuning choices and their current values, see the architecture doc directly.