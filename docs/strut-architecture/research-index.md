# STRUT Research Reference Index

Per-component index mapping each architectural element to its supporting sources. Organized by the structure of `docs/core-path-architecture.md` for direct cross-referencing.

## How this doc relates to architectural-decisions.md

STRUT maintains two complementary citation documents serving different reading patterns:

- **`architectural-decisions.md`** — the narrative. Reads top-to-bottom, organized by concern. Tells the story of why each load-bearing choice was made. Best when you're evaluating STRUT's approach or onboarding to the project.
- **`research-index.md`** (this doc) — the index. Organized by architecture component. Lets you look up "what sources support this part of the architecture." Best when you're authoring or updating a specific component and need the evidence base for that scope.

Both docs draw from the same research; the organization differs to serve different lookup patterns. When updating one, check the other for consistency.

## Source tiers

Each source is labeled by rigor tier so the strength of support for any decision is visible at a glance:

- **[R]** **Research** — Peer-reviewed academic papers or industry research reports with stated methodology and sample sizes. Strongest evidence.
- **[I]** **Industry report** — Company or consulting research without full methodology transparency. Citable but less defensible under scrutiny.
- **[P]** **Practitioner convention** — Rules of thumb, patterns, or observations from experienced practitioners. Useful heuristics, not empirical findings.
- **[A]** **Anthropic documentation** — Company engineering guidance. Authoritative for Claude-specific implementation mechanics; treated as guidance, not research.
- **[D]** **Design decision** — Not sourced to external research. Our judgment, stated explicitly so it can be owned as such.

A decision supported by multiple [R]-tier sources is well-grounded. A decision supported only by [P] or [D] sources is a judgment call. A decision marked [D] is ours to defend.

---

## Foundational Principles

### Sequential orchestration (one step at a time, not simultaneous)
- **[A] Anthropic Building Effective Agents (2025)**: "Prompt chaining decomposes a task into a sequence of steps, where each LLM call processes the output of the previous one."
- **[R] AGENTIF (Qi et al., NeurIPS 2025)**: Compliance degrades with both constraint count AND instruction length in agentic prompts. Sequential structure reduces simultaneous directive load.
- **[R] Curse of Instructions (Harada et al., ICLR 2025)**: success_all = success_individual^N. Rate of following ALL instructions drops exponentially with count.
- Platform coupling: None. Pattern applies to any LLM platform.

### Orchestrator-workers separation (skills dispatch, agents work)
- **[A] Anthropic Building Effective Agents (2025)**: "In the orchestrator-workers workflow, a central LLM dynamically breaks down tasks, delegates them to worker LLMs, and synthesizes their results."
- **[A] Anthropic Context Engineering (2025)**: "The lead agent focuses on synthesizing and analyzing the results."
- Platform coupling: Pattern is portable. Specific implementation (Claude Code skills + agents) is Claude-specific.

### Isolated context per worker agent
- **[A] Anthropic Subagent Docs**: "Each subagent runs in its own context window."
- **[A] Anthropic Context Engineering (2025)**: "Clear separation of concerns — detailed search context remains isolated within sub-agents."
- **[R] CooperBench (2025)**: 25% success when two agents collaborate vs ~50% single agent. Directly validates isolated single-task design.
- Platform coupling: Mechanism (`tools:`, `model:` frontmatter + automatic context isolation) is Claude Code-specific. Principle is portable.

### File contracts for inter-agent communication
- **[A] Anthropic Context Engineering (2025)**: Recommends that "detailed search context remains isolated within sub-agents" as a separation of concerns principle.
- **[D]** Specific format (`{skill, status}` minimum, JSON in `.pipeline/`) is a STRUT design decision.
- Platform coupling: None. Any system with a filesystem works.

### Mechanical enforcement over directive instruction
- **[R] AGENTIF (Qi et al., NeurIPS 2025)**: Tool specification constraints are one of the hardest constraint types for models to follow. Moving to mechanical enforcement removes a constraint in the most expensive category.
- **[A] Anthropic Subagent Docs**: Frontmatter `tools:` field restricts available tools regardless of instructions.
- Platform coupling: Frontmatter is Claude Code-specific. Tool restriction exists on most platforms (OpenAI function scoping, etc.) but via different mechanisms.

### Start minimal, add based on observed failures (reactive method)
- **[A] Anthropic Context Engineering (2025)**: "Start by testing a minimal prompt with the best model available to see how it performs on your task, and then add clear instructions and examples to improve performance based on failure modes found during initial testing."
- **[A] Anthropic Context Engineering (2025)**: "Finding the smallest possible set of high-signal tokens that maximize the likelihood of some desired outcome."
- **[A] Anthropic Building Effective Agents (2025)**: "Add complexity only when it demonstrably improves outcomes."
- Platform coupling: None.

### Directive cost scales with count and length
- **[R] AGENTIF (Qi et al., NeurIPS 2025)**: Both constraint count AND instruction length independently degrade compliance in agentic prompts.
- **[R] Curse of Instructions (Harada et al., ICLR 2025)**: Exponential degradation formula confirmed on general tasks.
- **[R] RECAST (ICLR 2026)**: Degradation pattern confirmed across models and constraint complexity levels, including most recent generation.
- Platform coupling: None. Finding is cross-model.

### Condition constraints are above-average cost
- **[R] AGENTIF (Qi et al., NeurIPS 2025)**: Condition constraints (if X then Y structure) are harder than simple format or content constraints. Anti-rationalization patterns are condition constraints.
- Platform coupling: None.

### Skills 500-line limit (orchestrator thinness)
- **[A] Anthropic Skill Best Practices**: "Keep SKILL.md body under 500 lines for optimal performance. The context window is a public good."
- Platform coupling: Specific limit is Claude Code-specific. Principle (shared context = tighter length discipline) is general.

---

## Agent Inventory

### Spec-first development (nothing implemented without approved spec)
- **[R] METR RCT (2025)**: 39pp perception-reality gap. Developers believed AI made them 24% faster but were 19% slower. Root cause: prompting AI before clarifying intent.
- **[I] Bain & Company (2025)**: Coding is 25-35% of idea-to-launch. "Speeding up these steps does little to reduce time to market if others remain bottlenecked."
- **[I] GitHub Agent Config Analysis (2026)**: Teams covering fewer than 4 specification areas saw quality drop below human baseline.
- Platform coupling: None.

### Merged spec-review agent (spec quality + testability in two-phase prompt)
- **[D] Design decision**: Merged from two separate agents (spec-review + validate-spec) during complexity reassessment. The two agents' checks overlapped significantly (3 of 4 validate-spec checks overlapped with spec-review), context isolation provided no contamination protection (the assessments are orthogonal — knowing a criterion is unambiguous provides no signal about whether it's independently testable), and separation caused iteration inefficiency (spec-write received feedback sequentially instead of simultaneously). Two-phase prompt structure preserves the conceptual distinction without the dispatch overhead.
- **[R] AGENTIF (Qi et al., NeurIPS 2025)**: Combined checklist of ~9 items is within Sonnet's reliable range. Separation would have doubled dispatches per spec cycle iteration for marginal independence benefit.
- Build-phase monitoring: track whether Phase 2 (testability) checks degrade over time. If they do, re-split.
- Platform coupling: None.

### Bounded spec (3-7 criteria, ≤5 tasks)
- **[R] Stanford/UC Berkeley**: Bounded specs prevent context overload (referenced in `.claude/rules/methodology.md`; specific paper citation pending).
- **[R] Curse of Instructions (Harada et al., ICLR 2025)**: Fewer constraints improve compliance (applied to criteria count).
- Platform coupling: None. Currently unenforced in spec-write — revisit once specs are produced in practice.

### Given/When/Then format for criteria
- **[D] Design decision**: Industry-standard BDD format chosen for independent testability — each criterion maps directly to a test assertion.
- Platform coupling: None.

### must_never folded into criteria as negative type (uniform handling)
- **[D] Design decision**. Rationale: reduces downstream agent complexity by eliminating special cases.
- Platform coupling: None.

### Plan mode directives for spec-write, impl-write-tests, impl-write-code
- **[R] METR RCT (2025)**: Root cause of 39pp perception gap was prompting AI before clarifying intent.
- **[R] AGENTIF (Qi et al., NeurIPS 2025)**: Planning reduces downstream constraint load because plan decisions are locked before execution-time constraints compound.
- Platform coupling: None. Pattern (plan before producing) works on any reasoning-capable model.

### TDD enforcement (impl-write-tests before impl-write-code)
- **[R] DORA Report (2025)**: TDD "more critical than ever" with AI. AI amplifies existing practices.
- **[R] CodeRabbit (2025)**: AI code has 1.7× more issues per PR (10.83 vs 6.45). Tests are structural defense.
- **[R] Sol-Ver (Lin et al., 2025)**: Verifier (test generator) drives quality in solver (code generator). 19.63% improvement via self-play.
- **[R] AlphaCode (Li et al., 2022, Science)**: Generate-and-filter paradigm — tests are the selection mechanism.
- **[R] AlphaEvolve (Novikov et al., 2025)**: Automated test suites as fitness function for continuous code evolution.
- Platform coupling: None.

### Tests as permanent assets (code is disposable)
- **[I] Darwin Gödel Machine (Sakana AI, 2025)**: Less-performant ancestor agents produced breakthrough descendants. Attachment to existing code is counterproductive.
- **[R] MSR (2026)**: Agent-generated code has more churn than human-authored code.
- **[R] GitClear (2024)**: 8× increase in duplicated code 2020-2024. Copy-paste surpassed refactoring.
- **[R] Carnegie Mellon Cursor study (2025)**: Code complexity +40% after AI tool adoption.
- Platform coupling: None.

### Sonnet as default model (not Opus)
- **[P] Observed pattern from STRUT development**: Sonnet follows process rules more literally; Opus produces higher-quality domain reasoning but worse process compliance.
- **[D] Cost rationale**: Opus is roughly 15× cost per call.
- Platform coupling: Model names are Claude-specific. Principle (use lower-tier model for structured tasks, higher-tier for reasoning-heavy tasks) is platform-agnostic.

### Opus for review-security (trust ON only)
- **[I] Apiiro (2025)**: 322% more privilege escalation paths in AI code — trust boundary reasoning requires above-average judgment.
- **[I] Veracode (2025)**: 45% of AI code introduces OWASP Top 10 vulnerabilities.
- Platform coupling: Model choice is Claude-specific. Principle (invest higher-capability model in trust-sensitive reasoning) is general.

### Haiku for git-tool (mechanical operations)
- **[D] Design decision** based on task complexity (git commands are deterministic formatting).
- Platform coupling: Model choice is Claude-specific.

### build-check as bash script, not agent
- **[D] Design decision**: commands are deterministic, no LLM reasoning adds value.
- **[A] Anthropic Context Engineering (2025)**: Aligned with principle of minimal context use.
- Platform coupling: None. Scripts are portable.

---

## Orchestrator Hierarchy

### Two-layer model (orchestration skills + worker agents)
- **[A] Anthropic Building Effective Agents (2025)**: Orchestrator-workers pattern.
- **[A] Anthropic Context Engineering (2025)**: Lead agent synthesizes, subagents do isolated work.
- Platform coupling: Specific mechanism (skill vs agent distinction) is Claude Code-specific.

### Sub-orchestrator context isolation
- **[A] Anthropic Context Engineering (2025)**: "Clear separation of concerns — detailed search context remains isolated within sub-agents."
- **[R] AGENTIF (Qi et al., NeurIPS 2025)**: Instruction length independently degrades compliance. Sub-orchestrators reset effective length.
- Platform coupling: Mechanism (session-inherited context for skills) is Claude Code-specific. Principle is portable.

### Orchestrator-level retry budgets (not agent self-retry)
- **[P] Addy Osmani**: Kill criteria after 3+ iterations.
- **[R] AGENTIF (Qi et al., NeurIPS 2025)**: Retry logic is complex conditional behavior — cheaper to handle in orchestrators with explicit routing than in agents as conditional directives.
- Platform coupling: None.

### Fail-fast in review chain (stop on first failure, don't accumulate)
- **[A] Anthropic Context Engineering (2025)**: "Smallest possible set of high-signal tokens."
- **[R] CodeRabbit (2025)**: Senior engineers spend 3.6× longer reviewing AI code (4.3 min per suggestion vs 1.2 min for human code). Efficient review requires focusing human attention on confirmed issues.
- Platform coupling: None.

### Spec cycle max 5 iterations
- **[D] Design decision** based on observed spec-refinement behavior.
- **[P] Addy Osmani**: Kill criteria after 3+ iterations (we allow 5 because spec phase has two reviewer types).
- Platform coupling: None.

### Review chain max 3 retries
- **[P] Addy Osmani**: Kill criteria after 3+ iterations.
- Platform coupling: None.

### Build check max 3 attempts
- **[P] Addy Osmani**: Same kill criteria principle applied to build verification.
- Platform coupling: None.

---

## File Contracts

### JSON result files with `{skill, status}` minimum
- **[A] Anthropic Context Engineering (2025)**: Structured output enables clear separation of concerns.
- **[D] Specific schema** (`{skill, status}` minimum) is a STRUT design decision.
- Platform coupling: None.

### Content files separate from result files
- **[D] Design decision**: content consumed by multiple downstream agents (spec.json), results consumed only by orchestrator for routing.
- Platform coupling: None.

### Agent-specific status vocabulary (not universal enum)
- **[D] Emerged from Read Truth development**. Different agents have naturally different success/failure distinctions.
- Platform coupling: None.

### `.pipeline/` directory as working state (gitignored)
- **[D] Design decision**: working state is ephemeral, not source code.
- Platform coupling: None.

### Classification log append-only (never deleted)
- **[D] Design decision**: history across runs is valuable; per-run directories clean between runs.
- Platform coupling: None.

---

## Human Gates

### Two gates in standard path (spec approval, PR review)
- **[R] Faros AI (2025)**: Individuals complete 21% more tasks and merge 98% more PRs, but PR review time increased 91%. Company-wide throughput showed 0% improvement. Review is the bottleneck.
- **[I] Cognition/Devin (2026)**: PR volume exceeds review capacity → rubber-stamp approvals.
- **[I] ACM Queue (2025)**: Developer role shifts to navigator/reviewer — review IS the work, not overhead.
- Platform coupling: None.

### Automated review before human review (pre-filter)
- **[R] CodeRabbit (2025)**: 3.6× longer review time for AI code. Pre-filtering by automated chain reduces what humans must verify manually.
- **[R] Faros AI (2025)**: 91% increase in review time consumed all individual productivity gains.
- Platform coupling: None.

### Resume from file state (pipeline survives human pauses)
- **[D] Design decision** grounded in solo-founder reality: humans work in non-contiguous time.
- Platform coupling: None.

### "Override, not approve" at spec approval gate
- **[D] Design principle**: spec approval means "make it mine" not "check AI's work."
- **[R] METR RCT (2025)**: Perception-reality gap comes from humans not doing enough work upfront.
- Platform coupling: None.

---

## Modifier System

### Two modifiers (trust + decompose) instead of tiers
- **[D] Design decision** — simplified from earlier three-tier system based on observed pattern: modifiers are more composable than tiers.
- Platform coupling: None.

### Trust modifier triggered by risk signals (auth, rls, schema, security, immutability, multi_tenant)
- **[I] Apiiro (2025)**: 322% more privilege escalation paths in AI code — requires explicit trust boundary naming.
- **[I] Veracode (2025)**: 45% of AI code introduces OWASP Top 10 vulnerabilities.
- **[R] CodeRabbit (2025)**: Security vulnerabilities 1.5-2× more frequent in AI code.
- Platform coupling: None.

### Decompose modifier triggered by 2+ architectural boundary crossings
- **[R] Curse of Instructions (Harada et al., ICLR 2025)**: Performance drops with scope. Decomposition keeps each pass within effective range.
- **[R] CooperBench (2025)**: Isolated single-task agents outperform multi-task approaches. Decompose ON preserves isolation at task level.
- **[R] Stanford/UC Berkeley**: Bounded specs prevent context overload.
- Platform coupling: None.

### MUST NEVER derivation from rules (trust ON)
- **[I] Apiiro (2025)**: Trust boundaries must be explicitly named.
- **[R] METR RCT (2025)**: Intent clarified from documented sources outperforms human recall under time pressure.
- Platform coupling: None.

### Security review as third review chain step (trust ON)
- **[I] Apiiro (2025)**: AI code requires explicit security review.
- **[R] CodeRabbit (2025)**: Security vulnerabilities 1.5-2× more frequent.
- Platform coupling: None.

### impl-describe-flow structured description (trust ON)
- **[A] Anthropic trends (2026)**: Shift from "reading code" to "validating system behavior."
- Platform coupling: None.

### Task 1 human gate (decompose ON)
- **[D] Design decision**: validate AI interpretation of spec before remaining tasks proceed.
- **[R] METR RCT (2025)**: Early correction prevents compounding misalignment.
- Platform coupling: None.

### Adversarial spec attack (guarded-decompose only)
- **[I] Apiiro (2025)**: Trust boundaries require explicit adversarial consideration.
- Platform coupling: None.

---

## Knowledge Capture

### Self-improving rules cycle (scan → gap → propose → approve → next scan reads)
- **[R] DORA Report (2025)**: Continuous improvement through automated feedback loops.
- Platform coupling: None.

### Root-cause analysis on trust ON (why the process produced the issue)
- **[R] DORA Report (2025)**: Blameless postmortem tradition — process improvement, not code critique.
- Platform coupling: None.

### Pipeline-friction trigger (flag difficulty regardless of risk level)
- **[R] DORA Report (2025)**: Without strong testing/automation, increased change volume → instability. Friction is early warning.
- Platform coupling: None.

### 30-minute rule for standard path (optional capture)
- **[D] Design decision**: balance capture value against solo-founder time budget.
- Platform coupling: None.

### update-capture proposes, human applies (never writes directly)
- **[R] Faros AI (2025)**: Human remains in control of substrate changes.
- Platform coupling: None.

---

## Source Inventory by Tier

### [R] Research — Peer-reviewed papers and methodologically transparent reports

**Academic (peer-reviewed):**
- **AGENTIF** — Qi et al. NeurIPS 2025 Datasets and Benchmarks Track (Spotlight). arxiv.org/abs/2505.16944
- **Curse of Instructions** — Harada et al. ICLR 2025. openreview.net/forum?id=R6q67CDBCH
- **RECAST** — ICLR 2026. arxiv.org/abs/2505.19030
- **AlphaCode** — Li et al. Science 2022. Generate-and-filter paradigm.
- **AlphaEvolve** — Novikov et al. 2025. Continuous evolutionary code optimization.
- **Sol-Ver** — Lin et al. 2025. Self-play solver-verifier improvement.
- **UTBoost** — ACL 2025. 40.9% of SWE-bench tasks affected by test quality issues.
- **CooperBench** — 2025. 25% multi-agent success vs ~50% single agent.
- **MSR 2026** — ~110,000 PRs analyzed; agent-generated code has more churn than human code.
- **Stanford/UC Berkeley** — Bounded specs prevent context overload (specific paper citation pending).

**Industry research with stated methodology:**
- **DORA Report 2025** — Annual research methodology. TDD more critical with AI; automated testing as control system.
- **METR RCT 2025** — Randomized controlled trial, 16 developers. 39pp perception-reality gap.
- **CodeRabbit 2025** — 470 PRs analyzed. 1.7× more issues, 3.6× longer review time, 10 architecture anti-patterns at 80-100% frequency.
- **Faros AI 2025** — Company-wide metrics. Individual +21% tasks, +98% PRs, +91% review time, 0% org improvement.
- **GitClear 2024** — 211M lines of code. 8× increase in duplicated code 2020-2024.
- **Carnegie Mellon Cursor study 2025** — 807 repositories. Code complexity +40% after AI adoption.

### [I] Industry reports — Stated findings, methodology less transparent

- **Bain & Company 2025** — Coding is 25-35% of idea-to-launch.
- **GitHub Agent Config Analysis 2026** — <4 specification areas → quality below human baseline.
- **Cognition/Devin 2026** — Company blog post. PR volume exceeds review capacity.
- **Apiiro 2025** — Vendor research. 322% more privilege escalation paths in AI code.
- **Veracode 2025** — Vendor research. 45% of AI code introduces OWASP Top 10.
- **Ox Security 2025** — Vendor research. "Highly functional but systematically lacking in architectural judgment."
- **Darwin Gödel Machine (Sakana AI 2025)** — Single-lab research. Evolutionary code self-rewriting.
- **ACM Queue 2025** — Industry publication. Navigator/reviewer role shift.

### [P] Practitioner conventions

- **Addy Osmani** — Kill criteria after 3+ iterations (blog/talk heuristic).
- **Observed pattern from STRUT development** — Sonnet process compliance, Opus domain reasoning.

### [A] Anthropic documentation

- **Building Effective Agents** — anthropic.com/research/building-effective-agents
- **Effective Context Engineering for AI Agents** — anthropic.com/engineering/effective-context-engineering-for-ai-agents
- **Skill Authoring Best Practices** — platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices
- **Agent Skills Overview** — platform.claude.com/docs/en/agents-and-tools/agent-skills/overview
- **Create Custom Subagents** — code.claude.com/docs/en/sub-agents
- **Extend Claude with Skills** — code.claude.com/docs/en/skills

### [D] Design decisions (our judgment, stated explicitly)

See each decision above for specific rationale. Summary: must_never folding into criteria, content/result file separation, agent-specific status vocabulary, `.pipeline/` directory convention, classification log append-only, specific JSON schema choices, model selection cost rationale, Haiku for git-tool, build-check as script, two-modifier system (vs tiers), task 1 human gate, 30-minute rule for standard path, spec cycle max 5 iterations, resume-from-file mechanism.

---

## How to use this index

**For authoring a component:** Find the component or decision in the index above, see which sources support it and at what tier. Decisions backed by multiple [R] sources are well-grounded. Decisions backed only by [P] or [D] sources are judgment calls — valid, but should be owned explicitly.

**For reviewing an implementation against intent:** When a component's behavior feels off, check the relevant section. If the implementation doesn't match what the sources suggest, either the code has drifted or the sources no longer support the original decision.

**For team scaling:** When bringing on collaborators, this index is the shared understanding of why the architecture is the way it is. The tier labels prevent "let's change X" conversations based on a [P] tier source overriding an [R] tier finding.

**For questioning a decision:** Walk the relevant entries. Ask: "Is this research actually proving what I'm claiming, or am I extrapolating?" Pay particular attention to [D] decisions — these are judgment calls that should be defensible on their own merits.
