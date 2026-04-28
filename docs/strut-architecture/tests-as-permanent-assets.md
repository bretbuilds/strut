# Tests Are the Permanent Asset. Code Is Disposable.

A research-grounded argument for why tests matter more than the code they verify in AI-driven development.

---

## The core argument

When AI agents write code, any implementation can be regenerated at any time. A better model, a different approach, or a full rewrite from scratch are all viable — IF the tests exist to verify the result is correct. Without tests, a rewrite is a gamble. With tests, it's a mechanical operation: generate new code, run tests, if they pass, the new code is valid.

Tests encode human intent. Code is just whatever happens to satisfy that intent today.

---

## What the research says

**DORA 2025** found TDD is "more critical than ever" with AI. AI amplifies existing practices — teams with strong testing get more value from AI, teams without it accumulate defects faster. The test suite is the foundation AI accelerates on top of. Without it, AI amplifies chaos.

**CodeRabbit (2025)** analyzed 470 GitHub pull requests and found AI-generated code produces 1.7× more issues per PR than human-written code (10.83 vs 6.45 issues). Logic and correctness issues were up 75%. Security vulnerabilities were 1.5-2× more frequent. Tests are the structural defense against this higher defect rate — they catch what the model gets wrong before it reaches production.

**MSR 2026** studied ~110,000 open source PRs across multiple AI coding agents (Codex, Claude Code, Copilot, Google Jules, Devin) and found that agent-generated code has more churn over time than human-authored code. Code written by AI today is more likely to need changing tomorrow. Tests protect against churn — they verify that changes don't break existing behavior regardless of who or what wrote the original code.

**GitClear (2024)** analyzed 211 million lines of code and found an 8× increase in duplicated code blocks from 2020-2024, with copy-pasted code surpassing refactored code for the first time in their dataset's history. Carnegie Mellon tracked 807 repositories that adopted Cursor and found code complexity rose by more than 40% after AI tool adoption. AI produces more code, but lower quality code — tests are what prevent this from compounding into unmaintainable systems.

**AlphaCode (Li et al., 2022, Science)** demonstrated the generate-and-filter paradigm: one million candidate programs generated per problem, 99% filtered through test execution, survivors clustered by behavior. The test suite IS the selection mechanism. Without it, generation is useless — you have a million programs and no way to know which ones work.

**AlphaEvolve (Novikov et al., 2025)** extends this to production code: continuous evolutionary optimization of existing codebases, with automated test suites as the fitness function. The code changes continuously. The tests determine whether each change is an improvement or a regression. Code is the variable. Tests are the constant.

**Sol-Ver (Lin et al., 2025)** uses self-play between a solver (generates code) and a verifier (generates tests). Each role improves the other iteratively, achieving 19.63% improvement in code generation without any human annotations. The verifier (test generator) drives quality improvements in the solver (code generator) — tests are the forcing function.

**Darwin Gödel Machine (Sakana AI, 2025)** rewrites its own source code through evolutionary self-play. A critical finding: less-performant ancestor agents sometimes produced breakthrough descendants. This proves empirically that attachment to existing code is counterproductive — you can't know in advance which implementation is best, so the ability to discard and regenerate (verified by tests) is more valuable than the code itself.

---

## The three types of AI-specific technical debt (and how tests defend against each)

From practitioner analysis documented across multiple sources (2025-2026):

**Cognitive debt** — shipping code faster than you can understand it. AI generates thousands of lines in minutes. Without tests, you're shipping behavior you haven't verified. Tests make the behavior explicit and verifiable without requiring you to read and understand every line of implementation.

**Verification debt** — approving diffs you haven't fully read. As PRs get larger and more frequent, the temptation to rubber-stamp grows. Tests convert approval from "I read this and it looks right" to "the automated suite verifies all specified behaviors pass." The human still reviews intent alignment, but correctness verification is handled by the test suite.

**Architectural debt** — AI generating working solutions that violate the system's design principles. Ox Security found AI-generated code is "highly functional but systematically lacking in architectural judgment," with 10 architecture anti-patterns appearing at 80-100% frequency. Tests that verify behavior (not implementation) survive architectural changes — when you regenerate the implementation to fix architectural problems, the tests confirm the behavior is preserved.

---

## What makes a test a permanent asset vs. a disposable artifact

A test is permanent (survives regeneration) when it:
- Tests behavior, not implementation — checks what the function produces, not how it produces it
- Maps to a human-specified criterion — the test exists because the human said "this behavior matters"
- Is independently verifiable — can run without knowledge of the current implementation's internal structure

A test is disposable (breaks on regeneration) when it:
- Tests implementation details — checks which functions were called, what internal state looks like, or how queries are structured
- Was written after implementation to confirm what the AI did — encodes the AI's interpretation, not the human's intent
- Is coupled to specific code structure — breaks if the implementation is refactored even though behavior is unchanged

The TDD sequence (tests before implementation) naturally produces permanent tests because the test is written from the human's criterion, not from the AI's code. The test cannot be coupled to implementation details that don't exist yet.

---

## Practical implication for STRUT

During the pipeline's change cycle, the spec is the contract. On merge, the spec is consumed — code and tests absorb the change. But if the code is disposable and regenerable, then after merge, it's really: **tests are the contract, code is the current implementation.**

Every test written through the pipeline is an investment that compounds:
- It verifies today's implementation during the change cycle
- It protects against regressions from future changes
- It enables future regeneration (a better model can rewrite the code and the test verifies correctness)
- It captures human intent in executable form that outlives any specific implementation

The implementation is the least durable part of the pipeline's output. The tests are the most durable.

---

## Sources

| Source | Year | Finding |
|--------|------|---------|
| DORA Report | 2025 | TDD "more critical than ever" with AI |
| CodeRabbit | 2025 | AI code: 1.7× more issues, security vulns 1.5-2× more frequent |
| MSR (agent contributions study) | 2026 | Agent-generated code has more churn than human code |
| GitClear | 2024 | 8× increase in duplicated code, copy-paste surpasses refactoring |
| Carnegie Mellon (Cursor study) | 2025 | Code complexity +40% after AI tool adoption |
| AlphaCode (Li et al.) | 2022 | Generate millions, filter through tests — tests are selection mechanism |
| AlphaEvolve (Novikov et al.) | 2025 | Continuous code evolution with test suite as fitness function |
| Sol-Ver (Lin et al.) | 2025 | Self-play: verifier (tests) drives 19.63% improvement in solver (code) |
| Darwin Gödel Machine (Sakana AI) | 2025 | Less-performant ancestors produce breakthroughs — no attachment to existing code |
| Ox Security | 2025 | AI code: "highly functional but systematically lacking in architectural judgment" |
| Veracode | 2025 | 45% of AI code introduces OWASP Top 10 vulnerabilities |
| Apiiro | 2025 | 322% more privilege escalation paths in AI code |
