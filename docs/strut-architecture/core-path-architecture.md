# STRUT Core Path Architecture

The standard path: trust OFF, decompose OFF. One pipeline, one task, two human gates.

This document defines the architecture for the core execution path — the simplest variant that every other path extends. Trust ON adds agents and deepens scrutiny. Decompose ON adds task iteration. Both modifiers add to this base; they never change its structure.

Grounded in: universal constraints (three-layer model), pre-build decisions (spec schema, cleanup, resume, PR rejection), and the two-layer orchestration model (skills dispatch, agents work).

### Platform coupling

This architecture is implemented on Claude Code specifically. The underlying patterns (sequential orchestration, file contracts, spec-first, TDD enforcement, isolated reviewer contexts, modifier-based risk routing) are platform-agnostic and grounded in research that studies LLMs generally. The implementation mechanisms (agent/skill distinction, frontmatter enforcement via `tools:` and `model:`, session-inherited orchestrator context, `.claude/` directory conventions) are Claude Code-specific.

Porting to another platform would preserve the architecture's substance while replacing its implementation layer. Agents (markdown files with task instructions) are fairly portable to any system that routes prompts to models and captures responses. Orchestrators (skills) are the Claude-specific glue — a portable version would replace them with a generic workflow engine reading the same registry files and dispatching to different LLM providers based on model configuration.

Portability is a deferred decision. Current priority is proving the architecture works on one platform.

---

## 0. Design Model

### Classification: two modifiers, one pipeline

Every pipelined change follows the same structure. Two independent modifiers — trust and decompose — control how much ceremony each step receives. This replaces the earlier three-tier system, which collapsed two independent concerns (risk and complexity) into a single number.

**Trust modifier** — does this change touch trust-sensitive systems? Determined by: `risk_signals` from the scan. Any signal true (auth, rls, schema, security, immutability, multi_tenant) → trust ON. Research basis: Apiiro (322% more privilege escalation in AI code), Veracode (45% OWASP violations), CodeRabbit (1.5-2× security vulns).

**Decompose modifier** — is this change too structurally complex for a single pass? Determined by: `boundary_crossings` from the scan. Crosses 2+ architectural boundaries (UI / server / database) → decompose ON. Research basis: Curse of Instructions (performance drops with scope), CooperBench (isolated single-task agents outperform multi-task).

| Trust | Decompose | Path | Human time estimate |
|-------|-----------|------|---------------------|
| OFF | OFF | standard | 15-25 min (spec review + PR review) |
| ON | OFF | guarded | 30-60 min (deeper spec + architectural PR review + knowledge capture) |
| OFF | ON | standard-decompose | 25-40 min (spec review + task 1 gate + PR review) |
| ON | ON | guarded-decompose | 1-2 hours (adversarial spec attack + task 1 gate + architectural review + knowledge capture + root-cause) |

**Fast-track:** Trivial changes (CSS fixes, typos, config tweaks) skip the pipeline entirely. The human talks to Claude Code directly without invoking `/run-strut`. This follows the ITIL "standard change" pattern — pre-approved, low-impact changes that don't need formal assessment.

### Why single-task agents

The single-task isolation constraint is the most important architectural decision. Each worker agent does exactly one task in fresh isolated context. Six independent findings support this:

1. **Context accumulation degrades output.** Curse of Instructions: performance drops as instruction count and context size increase, with compounding effect. An agent that scans, classifies, specs, and implements produces worse output than one that only implements — accumulated context dilutes focus. Operational testing confirmed a degradation zone above ~50% context utilization.

2. **Isolated context prevents cross-contamination.** Anthropic multi-agent research: subagent delegation with context isolation produces higher-quality output for tasks requiring verification or multiple perspectives. Directly applies to the review chain — if scope and security reviewers share context, the scope assessment biases the security judgment.

3. **Multi-agent outperforms single-agent for isolation and verification.** Anthropic Building Effective Agents: multi-agent consistently outperforms single-agent for context isolation and verification tasks. STRUT uses both.

4. **AI code has higher defect rates demanding independent review.** CodeRabbit: 1.7× more issues per PR. Faros AI: PR review time +91%. Independent review with isolated context prevents the reviewer from sharing the implementer's blind spots.

5. **Frontier models rationalize shortcuts with broad authority.** Operational testing: Opus rationalizes lower ceremony, launches autonomous exploration, substitutes its own logic. Narrow single-task mandates eliminate rationalization surface area.

6. **Different models excel at different tasks.** DORA 2025: AI amplifies existing practices. Sonnet is more process-compliant (implementation, sequential tasks); Opus produces higher-quality domain reasoning (security review). Single-task agents enable per-agent model selection.

### Why orchestration shares context

Orchestration skills share the session's main context. This seems to contradict isolation, but orchestration is not work — it's dispatch calls and file existence checks. The context footprint of "check if spec-review.json exists, then dispatch the next agent" is negligible. There's nothing to contaminate because there's no reasoning happening. Same pattern as a bash script that runs commands in sequence and checks exit codes.

Skills nesting freely (skills within skills) is the architectural advantage that enables sub-orchestrators like run-review-chain inside run-implementation. Agent nesting is not possible (Claude Code constraint: agents cannot spawn agents).

### Read Truth phase

The first phase of the pipeline. The human types one sentence. Read Truth replaces assumption with evidence before any planning begins.

`run-read-truth` orchestrates two agents sequentially:

1. **truth-repo-impact-scan** — reads the codebase and `.claude/rules/*`, produces `truth-repo-impact-scan-result.json` (structured risk/complexity signals) and `impact-scan.md` (human-readable evidence map). Context discarded.
2. **truth-classify** — reads the scan result file (fresh context, no residual scan reasoning), applies deterministic rules, produces `classification.json` (modifiers, execution path, evidence) and appends to `classification-log.md`. Context discarded.

Back in run-strut: shows classification to the human. Human can override modifiers or proceed to Process Change.

### Intent derivation and docs/user-context/

Before spec writing, spec-derive-intent reads scan evidence, project rules, and business context to produce structured intent. The `docs/user-context/` folder is the optional enrichment source:

What belongs there: product decisions, trust invariants beyond code-level rules, user expectations, domain vocabulary the AI might misinterpret. What doesn't belong: code documentation, API references, deployment config.

The pipeline works without this folder. It works better with it. spec-derive-intent degrades gracefully — empty folder means derivation from scan evidence alone, populated folder means richer specs. The human catches errors at the spec approval gate.

### Self-improving rules cycle

The scan reads `.claude/rules/*` for trust-sensitive definitions. When it detects a risk signal but finds no corresponding rule, it outputs a `rules_gaps` entry. After merge, update-capture reads those gaps and proposes specific rule text. The human reviews and applies. The next scan reads the new rule — the gap is closed.

This is the feedback loop that closes the system's blind spots through normal operation: scan detects gap → change is built → update-capture proposes rule → human approves → next scan reads the rule.

---

## 1. Agent Inventory

Eleven worker agents for the standard path. Two additional agents activate for trust ON. Each agent gets isolated context per dispatch, receives only its declared inputs, and writes a single result file.

### Spec Refinement Agents

| Agent | Role | Inputs | Output file | Model |
|-------|------|--------|-------------|-------|
| spec-derive-intent | Derive structured intent from scan evidence, rules, and business context | `classification.json`, `impact-scan.md`, `truth-repo-impact-scan-result.json`, `.claude/rules/*`, `docs/user-context/` (optional) | `.pipeline/spec-refinement/intent.json` | Sonnet |
| spec-write | Draft spec with Given/When/Then criteria, implementation notes, and out-of-scope | `intent.json`, `impact-scan.md`, `truth-repo-impact-scan-result.json`, `classification.json`; on revision: `spec-review.json` | `.pipeline/spec-refinement/spec.json` | Sonnet |
| spec-review | Check spec quality (ambiguity, gaps, completeness) and testability (independence, compound criteria, external dependencies) | `spec.json` | `.pipeline/spec-refinement/spec-review.json` | Sonnet |

**spec-derive-intent** reads the scan evidence and project rules to produce structured intent before spec writing. For standard path (trust OFF): produces `user_sees` and `business_context`. The `must_never` array is empty — trust OFF means no risk signals fired. The agent always runs; its output richness depends on what reference material exists in `docs/user-context/`.

**spec-write** produces the spec JSON matching the locked schema from pre-build decisions. For standard path: criteria are positive type only (no negative/must_never entries). `tasks[]` contains exactly one task with all `criteria_ids`. `implementation_notes` copied from `impact-scan.md`. `out_of_scope` requires at least one entry. Before writing the spec, the agent runs a self-audit that cross-checks the planned criteria against `intent.json` requirements and `must_never` entries — catching omissions while the context is hot, before spec-review sees it.

**spec-review** gets fresh context with only the spec. It performs a two-phase assessment:

*Phase 1 — Spec Quality:* Are criteria unambiguous? Are there gaps (behaviors implied by what/user_sees but not specified)? Does out_of_scope have at least one entry and define clear boundaries? Are implementation_notes consistent with the criteria?

*Phase 2 — Testability:* Can impl-write-tests produce a test for each criterion independently — without depending on other criteria being satisfied first? Does any criterion bundle unrelated behaviors that should be separate criteria? Is each criterion's expected outcome (the `then` clause) measurable and assertable? Does any criterion depend on external state not available in a test environment?

The agent body includes a distinction anchor: "A criterion can be unambiguous but untestable — 'the system feels responsive' is clear in intent but has no assertable threshold. A criterion can be ambiguous but testable — 'data is processed quickly' is vague but you could write a latency test. Check these independently."

Output separates the two assessment types: `review_issues` and `validation_issues` arrays, each with a `criterion_id`, `type`, and `issue` description. This lets spec-write understand the nature of each issue and fix all problems in one revision rather than discovering them sequentially across iterations. Returns `passed` or `failed` with specifics.

### Implementation Agents

| Agent | Role | Inputs | Output file | Model |
|-------|------|--------|-------------|-------|
| git-tool | Git operations: branch, commit, or PR | Mode-specific inputs (see below) | Mode-specific (see below) | Haiku |
| impl-write-tests | Write one test per criterion, verify all fail | `spec.json` (filtered to task-1 criteria_ids) | `.pipeline/implementation/task-1/tests-result.json` | Sonnet |
| impl-write-code | Write minimum code to pass tests | `spec.json`, test files, `implementation_notes`; on retry: `review-chain-result.json` | `.pipeline/implementation/task-1/impl-write-code-result.json` | Sonnet |

**git-tool** is one agent with three modes, dispatched at different points:

- **branch mode** — Creates `feature/[change-slug]` from main. Input: `classification.json` (for the `what` field to derive branch name). Output: `.pipeline/implementation/git-branch-result.json`. Skipped on resume if branch exists.
- **commit mode** — Commits staged changes. Input: task description from `spec.json`. Output: `.pipeline/implementation/task-1/git-commit-result.json`. Commit message derived from task description.
- **pr mode** — Opens pull request. Input: `spec.json` (for PR body), file list from diff, `impl-describe-flow.txt` (if trust ON). Output: `.pipeline/git-pr-result.json`. Dispatched by run-process-change, not run-implementation.

**impl-write-tests** reads the spec, filters to task-1's criteria_ids (for standard path, this is all criteria), and writes test files to the branch. Each positive criterion maps to at least one positive test. The `criteria_coverage` field in its result file maps each test to its criterion in natural language — this is what the human reads at the PR gate to verify test-criterion alignment. Before running the test suite, the agent runs a self-audit that re-reads each criterion's full `then` clause and verifies every required assertion exists in the test code. This is the strongest self-audit case: impl-write-tests has no downstream review agent, so the tests become the contract that everything else is measured against — a missing assertion here means the implementation can satisfy the test without satisfying the criterion. After writing tests, it runs the test suite and verifies all new tests fail. If any test passes before implementation, something is wrong — either the test is trivial or existing code already satisfies it. Result: `passed` (all tests written and failing) or `failed` (with specifics).

**impl-write-code** reads the spec, the test files, and the implementation notes. It writes minimum code to make all tests pass. No refactoring beyond what tests require. No changes to files not in `implementation_notes.files_to_modify`. On retry after review chain failure: also reads `review-chain-result.json` for specific feedback. Result: `passed` (all tests pass) or `failed` (with what's still failing).

### Review Chain Agents

| Agent | Role | Inputs | Output file | Model |
|-------|------|--------|-------------|-------|
| review-scope | Check implementation stays within spec scope | diff, `spec.json` (criteria + out_of_scope) | `.pipeline/implementation/task-1/review-scope.json` | Sonnet |
| review-criteria-eval | Check each criterion has a passing test and is satisfied | diff, `spec.json` (criteria), test results | `.pipeline/implementation/task-1/review-criteria-eval.json` | Sonnet |

**review-scope** reads the diff and the spec. Its question: "Did the implementation touch only what the spec says to touch?" Flags additions not covered by criteria, modifications to files not in `files_to_modify`, and removals not justified by the change. Returns `passed` or `failed` with specific scope violations.

**review-criteria-eval** reads the diff and criteria. Its question: "Is each criterion satisfied, and does each criterion have a corresponding passing test?" It checks the mapping between criteria, tests, and implementation. If a criterion lacks a test, or a test exists but doesn't actually verify the criterion's behavior, it fails. Returns `passed` or `failed` with per-criterion status.

Both reviewers get isolated context. Neither sees the other's assessment. This prevents one reviewer's reasoning from biasing the next — a design validated by the isolated single-task agent approach from CooperBench.

#### Trust ON Plugin: review-security

| Agent | Role | Inputs | Output file | Model |
|-------|------|--------|-------------|-------|
| review-security | Check for trust boundary violations | diff, `.claude/rules/*`, must_never entries from spec | `.pipeline/implementation/task-1/review-security.json` | Opus |

Third step in the review chain when trust is ON. Dispatched by run-review-chain after review-criteria-eval passes. Uses Opus for domain reasoning about trust boundaries. Checks for: tenant-leak paths, auth bypasses, missing validations, RLS gaps, service role key usage, anything violating named trust invariants. The review chain's fail-fast and retry behavior applies identically.

### Build Verification

| Component | Role | Inputs | Output file | Type |
|-----------|------|--------|-------------|------|
| build-check | Run full verification suite | Branch code | `.pipeline/build-check/build-check.json` | **Bash script** |
| build-error-cleanup | Fix build errors on failure | Build errors from `build-check.json` | `.pipeline/build-check/build-error-cleanup.json` | Agent (Sonnet) |

**build-check** is a bash script, not an agent. It detects the project's toolchain and runs the appropriate build, lint, typecheck, and test commands — then captures exit codes and error output and writes the result JSON to `.pipeline/build-check/build-check.json`. See `.claude/scripts/build-check.sh` for supported toolchains (Node.js with npm/pnpm/yarn/bun, Rust, Go, Python, Makefile) and `.strut/build.json` for override configuration on unsupported stacks. Every defined check runs even if an earlier one fails, so build-error-cleanup gets the full picture. No LLM reasoning needed — the commands are deterministic. A script is cheaper, faster, and more reliable than an agent for this task. The orchestrator (run-build-check) reads the result file identically regardless of whether a script or agent produced it.

**build-error-cleanup** stays as an agent because fixing errors requires reasoning about code. Only runs if build-check fails. Reads the error output and attempts targeted fixes. Does not refactor, does not add features, does not change test expectations. Only fixes build/lint/type/test errors. Max 3 attempts (managed by run-build-check).

#### Trust ON Plugin: impl-describe-flow

| Agent | Role | Inputs | Output file | Model |
|-------|------|--------|-------------|-------|
| impl-describe-flow | Produce structured data flow description | diff, `spec.json`, `impact-scan.md` | `.pipeline/impl-describe-flow.txt` | Sonnet |

Dispatched by run-process-change after build-check passes, before PR creation. Produces a structured text description of data flow after the change — not the diff, but the end state. Included in PR body for human validation.

### Knowledge Capture Agent

| Agent | Role | Inputs | Output file | Model |
|-------|------|--------|-------------|-------|
| update-capture | Propose knowledge updates post-merge | diff, `spec.json`, review results, `rules_gaps` from scan, upstream result files (spec-review, review-chain-result, build-result) | `.pipeline/update-truth/knowledge-proposals.json` | Sonnet |

**update-capture** reads what changed (diff), what was intended (spec), what reviewers found (review chain results), and what rules were missing (rules_gaps from the scan). Proposes updates to decisions log, system map, and rules files. Never writes directly — the human reviews and applies. For standard path: no root-cause analysis (that's trust ON).

Additionally, update-capture checks pipeline friction regardless of trust level or the 30-minute rule. It reads upstream result files to detect: spec cycle exceeded 1 iteration (multiple `spec-review.json` writes), review chain retried (failure entries in `review-chain-result.json`), or build-check required build-error-cleanup (`build-error-cleanup.json` exists). If any friction is detected, it includes a `process_friction` entry in its proposals describing what caused the extra cycles and what might prevent them next time — whether that's a missing rule, an unclear pattern, or an agent directive that needs tuning. This is the pipeline's self-improvement signal: difficulty during a change means something about the substrate (rules, patterns, directives) can be improved.

### Model Selection Rationale

**Sonnet** for all standard-path agents. Follows process rules more literally than Opus — the right fit for agents that need to follow schemas, check criteria, write tests to spec, and stay in scope. Lower cost per dispatch.

**Haiku** for git-tool. Git operations are mechanical — create branch, commit, open PR. No reasoning required beyond formatting.

**Opus** for review-security (trust ON only). Trust boundary reasoning requires domain judgment that Sonnet handles less reliably. This is the one agent where quality of reasoning justifies the cost premium.

**Session model (Sonnet)** for all orchestrator skills. Skills inherit the session model. Orchestrators need to dispatch agents and check file statuses — Sonnet is sufficient.

### Plan Mode Directives

Three agents require a "plan before producing" directive in their agent body. These are the agents where jumping straight to output is the most dangerous failure mode — skipping structured reasoning leads to gaps, coupling, and scope creep that the review chain then has to catch.

**spec-write** — Must plan which criteria to include, what out_of_scope entries matter, and how implementation_notes map to the change *before* drafting the spec JSON. Directive: "Before producing spec.json, write a numbered plan: list each criterion you will include, each out_of_scope entry, and which files from the scan map to implementation_notes. Then produce the spec."

**impl-write-tests** — Must plan the test strategy before writing test code. Directive: "Before writing any test code, write a numbered plan: for each criterion, state what the test will assert, what fixture or setup is needed, and what the expected outcome is. Then write the tests."

**impl-write-code** — Must plan which files to modify and in what order before writing code. Directive: "Before modifying any files, write a numbered plan: list each file you will change, what the change is, and how it connects to the test it satisfies. Then implement the plan."

These are single directives per agent — not architecture changes. They're specified here because they're known requirements, not reactive additions. The specific wording may be adjusted during agent testing if the model responds better to different phrasing.

### Self-Audit Directives

Two agents include a self-audit step between planning and output. Self-audit catches errors of omission while the generation context is hot — complementing the cold-context review chain downstream.

**spec-write** — After planning, audits the planned spec against `intent.json`: checks that every `user_sees` requirement and every `must_never` entry has a corresponding criterion, that immutability constraints produce criteria for both app and db layers, that `criteria_ids` union is complete, and that file paths come from the scan. Catches omissions that would otherwise require a spec-review → spec-write retry cycle.

**impl-write-tests** — After writing tests, audits each test against its criterion's full `then` clause: checks that every required assertion exists, and that negative tests check for active rejection. This is the strongest self-audit case — impl-write-tests has no downstream review agent, so the self-audit is the only quality gate before tests become the contract.

**impl-write-code** — Deferred. Test execution is a deterministic verifier for implementation correctness. A probabilistic self-audit before a deterministic verifier provides no demonstrated value.

---

## 2. Orchestrator Hierarchy

Eight skills total. One top-level entry point, two phase orchestrators, four sub-orchestrators, plus the already-built Read Truth orchestrator.

```
run-strut (SKILL — human entry point)
│
├── run-read-truth (SKILL — phase orchestrator, ALREADY BUILT)
│   ├── truth-repo-impact-scan (AGENT — already built)
│   └── truth-classify (AGENT — already built)
│
├── run-process-change (SKILL — phase orchestrator)
│   │
│   ├── run-spec-refinement (SKILL — sub-orchestrator)
│   │   ├── spec-derive-intent (AGENT)
│   │   ├── spec-write (AGENT)
│   │   └── spec-review (AGENT)
│   │       └── [spec cycle: if failed → spec-write reruns with feedback, max 5 iterations]
│   │
│   ├── ★ HUMAN GATE: Spec Approval
│   ├── ★ HUMAN GATE: Adversarial Spec Attack [guarded-decompose only]
│   │
│   ├── run-implementation (SKILL — sub-orchestrator)
│   │   ├── git-tool (AGENT, mode: branch)
│   │   ├── impl-write-tests (AGENT)
│   │   ├── impl-write-code (AGENT)
│   │   ├── run-review-chain (SKILL — sub-orchestrator)
│   │   │   ├── review-scope (AGENT)
│   │   │   └── review-criteria-eval (AGENT)
│   │   │       └── [if any fails → impl-write-code reruns with feedback, max 3 retries]
│   │   └── git-tool (AGENT, mode: commit)
│   │       └── [decompose ON: ★ HUMAN GATE: Task 1 after first task's commit]
│   │
│   ├── run-build-check (SKILL — sub-orchestrator)
│   │   ├── build-check (BASH SCRIPT)
│   │   └── build-error-cleanup (AGENT, on failure only)
│   │       └── [build-check → build-error-cleanup cycle, max 3 attempts]
│   │
│   ├── git-tool (AGENT, mode: pr) — dispatched by run-process-change directly
│   │
│   ├── ★ HUMAN GATE: PR Review
│   │
│   └── [Human merges → run-process-change returns "passed"]
│
└── run-update-truth (SKILL — phase orchestrator)
    └── update-capture (AGENT)
```

### How each orchestrator works

**run-strut** — The human entry point. Receives the change description from the human. Dispatches run-read-truth. On return, reads `classification.json` to confirm the change was classified. Dispatches run-process-change. On return, dispatches run-update-truth. This is the thinnest orchestrator — three sequential dispatches with status checks between them. On resume: reads state files to determine which phase completed, skips completed phases.

**run-process-change** — The phase orchestrator for the change cycle. This is the largest skill in the pipeline. It handles:
1. Check for new run vs. resume (pre-build decision #3: compare `what` fields)
2. If new run: clean Process Change directories (pre-build decision #2)
3. Dispatch run-spec-refinement
4. On return: pause at spec approval gate (write state, exit)
5. On resume after spec approval: check adversarial spec attack gate (guarded-decompose only, Step 6b)
6. On resume or pass-through: dispatch run-implementation
7. On return: if blocked at task_1 gate (decompose ON), pause for human validation (Step 7b). If passed, dispatch run-build-check
8. On return: dispatch git-tool (mode: pr)
9. Pause at PR review gate (write state, exit)
10. On resume after PR approval: return `passed` to run-strut
11. If PR rejected: handle rejection path (pre-build decision #4)

For trust ON: insert impl-describe-flow dispatch between step 7 and the PR gate. The impl-describe-flow output is passed to git-tool (mode: pr) for inclusion in the PR body.

**run-spec-refinement** — Sub-orchestrator for the spec cycle. Sequential dispatch:
1. Dispatch spec-derive-intent
2. Read `intent.json` status — if failed, return failed
3. Dispatch spec-write
4. Read `spec.json` status
5. Dispatch spec-review
6. Read `spec-review.json` — if failed, go to step 3 with feedback (spec cycle)
7. If spec cycle exceeds 5 iterations: return `failed` with latest feedback (run-process-change escalates to human)
8. Return `passed`

Iteration counter is internal to this orchestrator. Each spec-write re-dispatch includes the feedback from spec-review (both review_issues and validation_issues in one file). Write-spec gets all feedback simultaneously and can fix quality and testability issues in one revision.

**run-implementation** — Sub-orchestrator for the TDD cycle. Sequential dispatch:
1. Dispatch git-tool (mode: branch) — skip if branch exists
2. Dispatch impl-write-tests
3. Read `tests-result.json` — if failed, return failed (escalate)
4. Dispatch impl-write-code
5. Read `impl-write-code-result.json` — if failed, return failed (escalate)
6. Dispatch run-review-chain
7. Read `review-chain-result.json` — if failed, go to step 4 with feedback (max 3 retries)
8. If retries exhausted: return failed (escalate)
9. Dispatch git-tool (mode: commit)
10. Return `passed`

For decompose ON: steps 2-9 repeat per task. After task 1: return to run-process-change for human gate. The orchestrator writes its state including `completed_tasks` and `remaining_tasks`.

**run-review-chain** — Sub-orchestrator for the review sequence. Sequential dispatch with fail-fast:
1. Dispatch review-scope
2. Read `review-scope.json` — if failed, return failed immediately with feedback
3. Dispatch review-criteria-eval
4. Read `review-criteria-eval.json` — if failed, return failed immediately with feedback
5. Write `review-chain-result.json` with aggregated status
6. Return `passed`

For trust ON: insert review-security as step 5-6 (after review-criteria-eval, before writing result).

On retry (called again by run-implementation after impl-write-code revises): always re-run from review-scope. The revised implementation may have introduced new scope issues even if scope passed on the prior dispatch. All stale reviewer files are removed before each dispatch — every review chain execution starts clean.

**run-build-check** — Sub-orchestrator for build verification.
1. Run build-check script
2. Read `build-check.json` — if passed, write `build-result.json` with `passed`, return
3. If failed: dispatch build-error-cleanup agent
4. Re-run build-check script
5. If still failing: repeat steps 3-4, max 3 total attempts
6. If still failing after 3: write `build-result.json` with `failed`, return

**run-update-truth** — Phase orchestrator for post-merge knowledge capture.
1. Create `.pipeline/update-truth/` directory
2. Dispatch update-capture
3. Read `knowledge-proposals.json`
4. Return status to run-strut

The human reviews and applies proposals outside the pipeline. For standard path: knowledge proposals are optional under the 30-minute rule, but `process_friction` entries are always surfaced — pipeline difficulty is always worth reviewing. For trust ON: all proposals are mandatory.

### Context Budgets

Each sub-orchestrator gets fresh context within the shared session. The dispatch-check-dispatch pattern keeps per-orchestrator context lean.

| Orchestrator | Estimated dispatch cycles | Context pressure |
|---|---|---|
| run-strut | 3 | Minimal — three phase dispatches |
| run-process-change | 5-8 | Moderate — sub-orchestrator dispatches + gate handling + resume logic |
| run-spec-refinement | 3-5 | Low-moderate — depends on spec cycle iterations |
| run-implementation | 3-5 | Low-moderate — single task in standard path |
| run-review-chain | 2-3 | Low — two reviewers + result aggregation |
| run-build-check | 1-4 | Low — one check + up to 3 cleanup cycles |
| run-update-truth | 1-2 | Minimal — one agent dispatch |

All well within safe range (<50% context utilization per orchestrator).

---

## 3. File Contracts

### Directory Structure

```
.pipeline/
  # Read Truth (flat, unchanged — already built)
  truth-repo-impact-scan-result.json
  impact-scan.md
  classification.json
  classification-log.md          # append-only, never deleted

  # Process Change (namespaced)
  spec-refinement/
    intent.json                  # spec-derive-intent output
    spec.json                    # spec-write output (the central contract)
    spec-review.json             # spec-review output (quality + testability)

  implementation/
    git-branch-result.json       # git-tool (branch mode) output
    implementation-status.json   # run-implementation state for resume
    active-task.json             # run-implementation writes before each task's cycle; agents read for task id
    task-1/
      tests-result.json          # impl-write-tests output
      impl-write-code-result.json      # impl-write-code output
      review-scope.json          # review-scope output
      review-criteria-eval.json         # review-criteria-eval output
      review-security.json       # trust ON only
      review-chain-result.json   # run-review-chain aggregated result
      git-commit-result.json     # git-tool (commit mode) output

  build-check/
    build-check.json             # build-check output
    build-error-cleanup.json           # build-error-cleanup output (if dispatched)
    build-result.json            # run-build-check final result

  impl-describe-flow.txt              # trust ON only
  git-pr-result.json             # git-tool (pr mode) output

  update-truth/
    knowledge-proposals.json     # update-capture output

  process-change-state.json      # phase-level resume state
```

### Complete File Contract Table

Every read/write relationship in the standard path.

| File | Written by | Read by | Status values |
|------|-----------|---------|---------------|
| `classification.json` | truth-classify | run-process-change, spec-derive-intent, spec-write | `classified` |
| `impact-scan.md` | truth-repo-impact-scan | spec-write, impl-describe-flow | n/a (prose) |
| `truth-repo-impact-scan-result.json` | truth-repo-impact-scan | spec-derive-intent, spec-write | `passed` |
| `intent.json` | spec-derive-intent | spec-write | `passed`, `failed` |
| `spec.json` | spec-write | spec-review, impl-write-tests, impl-write-code, review-scope, review-criteria-eval, update-capture, git-tool (pr) | `drafted` |
| `spec-review.json` | spec-review | run-spec-refinement | `passed`, `failed` |
| `git-branch-result.json` | git-tool (branch) | run-implementation | `created`, `exists` |
| `tests-result.json` | impl-write-tests | run-implementation | `passed`, `failed` |
| `impl-write-code-result.json` | impl-write-code | run-implementation | `passed`, `failed` |
| `review-scope.json` | review-scope | run-review-chain | `passed`, `failed` |
| `review-criteria-eval.json` | review-criteria-eval | run-review-chain | `passed`, `failed` |
| `review-chain-result.json` | run-review-chain | run-implementation, update-capture | `passed`, `failed` |
| `git-commit-result.json` | git-tool (commit) | run-implementation | `committed` |
| `build-check.json` | build-check (script) | run-build-check | `passed`, `failed` |
| `build-error-cleanup.json` | build-error-cleanup | run-build-check | `fixed`, `failed` |
| `build-result.json` | run-build-check | run-process-change | `passed`, `failed` |
| `impl-describe-flow.txt` | impl-describe-flow | git-tool (pr) | n/a (prose, trust ON only) |
| `git-pr-result.json` | git-tool (pr) | run-process-change | `opened` |
| `knowledge-proposals.json` | update-capture | human | `passed` |
| `pr-rejection-feedback.json` | run-process-change | spec-write (loop_target: spec), impl-write-code (loop_target: implementation) | n/a (feedback file, not status-routed) |
| `process-change-state.json` | run-process-change | run-process-change (on resume) | `blocked`, `passed`, `failed`, `aborted` |
| `implementation-status.json` | run-implementation | run-process-change | `blocked`, `passed`, `failed` |
| `active-task.json` | run-implementation | impl-write-tests, impl-write-code, review-scope, review-criteria-eval, review-security | n/a (state file, contains `task_id`) |

### File Contract Rules

**Every agent writes a result file.** Minimum fields: `{ "skill": "[agent-name]", "status": "[value]" }`. Additional fields are agent-specific.

**Orchestrators read only the `status` field to route.** They never read content fields from agent results. If an agent needs to pass content to a downstream agent, it writes a separate content file that the downstream agent reads directly.

**Status vocabulary is agent-specific.** Each agent declares its own status values. Orchestrators declare which values they check. This is documented in the file contract table above.

**Test files and implementation code live on the branch, not in `.pipeline/`.** Only metadata (result files with status and summary) goes to `.pipeline/`. The actual code is committed to git.

**Content files are separate from result files.** `spec.json` is a content file (consumed by 5+ downstream agents). `spec-review.json` is a result file (consumed only by run-spec-refinement for routing). This distinction matters because content files have multiple consumers while result files have one.

---

## 4. Human Gates

Two gates in the standard path. Modifiers add more: decompose ON adds a task 1 gate, guarded-decompose adds an adversarial spec attack gate (see Section 5). Each gate writes state and exits. Re-invocation resumes.

### Gate 1: Spec Approval

**When:** After run-spec-refinement returns `passed`.

**What the human sees:**
- `spec.json` — the full spec including criteria (Given/When/Then), implementation notes, and out_of_scope
- `intent.json` — the AI-derived `user_sees` and `business_context` (verify the AI understood the change correctly)
- `spec-review.json` — what the reviewer checked and confirmed (both quality and testability assessments)

**What the human checks (5-10 minutes for standard path):**
- Does `user_sees` match your intent?
- Are the criteria complete — does each one describe a behavior you want?
- Are there missing criteria — behaviors you want that aren't listed?
- Does `out_of_scope` correctly exclude things that should wait?
- Do the `implementation_notes` point to the right files?

**Human choices:**
- **Approve** → Pipeline continues to implementation
- **Revise** → Human edits spec.json directly or provides feedback; pipeline re-runs validation only (not the full spec cycle)
- **Reject** → Pipeline stops; human re-invokes with a different approach

**State written:**
```json
{
  "status": "blocked",
  "gate": "spec_approval",
  "what": "Add response action for action items",
  "completed": ["read_truth", "spec_refinement"],
  "next": "implementation"
}
```

### Gate 2: PR Review

**When:** After git-tool (mode: pr) returns `opened`.

**What the human sees:**
- The PR on GitHub with: spec summary, acceptance criteria, files changed
- `criteria_coverage` from `tests-result.json` — natural language mapping of tests to criteria
- Review chain results — what review-scope and review-criteria-eval checked and passed
- Build check result — confirmation that build, lint, typecheck, and tests all pass

**What the human checks (5-10 minutes for standard path):**
- Does the diff match the spec's scope? (automated review already checked this — human validates at a higher level)
- Does the `criteria_coverage` mapping make sense? (each criterion should have a test that obviously verifies it)
- Are there any changes that feel wrong even though automated checks passed? (human judgment catches what rules can't)

**Human choices:**
- **Merge** → Human merges the PR; pipeline continues to Update Truth
- **Reject with "implementation" target** → run-process-change writes feedback, re-dispatches run-implementation (same spec, revised code)
- **Reject with "spec" target** → run-process-change writes feedback, wipes implementation, re-dispatches run-spec-refinement (pre-build decision #4)
- **Reject with "abort"** → Pipeline stops entirely

**State written (on pause):**
```json
{
  "status": "blocked",
  "gate": "pr_review",
  "what": "Add response action for action items",
  "completed": ["read_truth", "spec_refinement", "implementation", "build_check", "pr_opened"],
  "next": "awaiting_merge"
}
```

**State written (on rejection):**
```json
{
  "status": "blocked",
  "gate": "pr_rejection",
  "loop_target": "implementation",
  "feedback": "The response action should validate that the action item hasn't already been responded to",
  "what": "Add response action for action items",
  "completed": ["read_truth", "spec_refinement"],
  "next": "implementation"
}
```

### Gate Behavior on Resume

When the human re-invokes `/run-strut`:
1. run-strut reads `process-change-state.json` — if `status == "blocked"`, this is a Process Change resume. Skip Read Truth and go directly to step 3
2. Otherwise (new run): run-strut dispatches run-read-truth, shows classification, then dispatches run-process-change
3. run-process-change reads `process-change-state.json`
4. Compares `what` fields (pre-build decision #3)
5. If match → resume: check `completed` array, skip completed stages, continue from `next`
6. If mismatch → new run: clean directories (pre-build decision #2), start fresh

---

## 5. Modifier Details

The standard path (trust OFF, decompose OFF) is the base. Modifiers add to it — they never change the structure. Each modifier change uses one of three mechanisms: conditional directives inside an existing agent (mechanism A), conditional dispatch in an orchestrator (mechanism B), or conditional loop structure in an orchestrator (mechanism C).

### What trust ON adds

| Component | Change | Mechanism |
|-----------|--------|-----------|
| spec-derive-intent | Populates `must_never` array from risk signals + rules (empty in standard path) | A — conditional directive |
| spec-write | Creates negative-type criteria from `must_never` entries, each with `source` tracing to intent | A — conditional directive |
| run-review-chain | Dispatches review-security (Opus) as third step after review-criteria-eval | B — conditional dispatch |
| run-process-change | Dispatches impl-describe-flow before git-tool (pr), includes output in PR body | B — conditional dispatch |
| update-capture | Mandatory knowledge capture (not optional). Populates `root_cause` field analyzing what the review chain caught and why | A — conditional directive |
| Human gates | Spec approval: 15-30 min architectural review (vs 5-10). PR review: validates data flow description against mental model, reviews schema migrations, checks RLS for independent tenant enforcement | Behavioral — no code change |

### What decompose ON adds

| Component | Change | Mechanism |
|-----------|--------|-----------|
| spec-write | Produces task breakdown (≤5 tasks, each independently testable) instead of single task. Each task gets a subset of criteria_ids | A — conditional directive |
| spec-review | Adds Phase 3: decomposition validation — each task must be context-fit, eval-fit, merge-fit, and dependency-fit | A — conditional directive |
| run-implementation | Iterates the TDD cycle (impl-write-tests → impl-write-code → review chain → commit) per task instead of once. Human gate after task 1 validates AI interpretation before remaining tasks proceed | C — conditional loop |
| Human gates | Task 1 gate added between first and subsequent tasks. If wrong: stop, clarify spec, restart from task 1. If right: remaining tasks proceed without gate | Behavioral |

### Guarded-decompose (both ON)

Combines all trust ON and decompose ON additions. Additionally: human performs adversarial spec attack in a separate Claude.ai session after spec approval — "What's wrong with this spec? What edge cases are missing? What could go wrong?" This is a human activity, not a pipeline agent. Most ceremony-heavy scrutiny point in the pipeline. Human time: 1-2 hours total.

---

## 6. Build Order

Dependencies flow top-down. Build and test each component before wiring it into its orchestrator. This follows the Read Truth pattern: skills tested as skills first, converted to agents once proven.

### Phase 0: Foundation (already done)
- Read Truth agents and orchestrators — built and tested
- Universal constraints — locked
- Pre-build decisions — locked

### Phase 1: Spec Refinement (build first — everything depends on the spec)

**Build order within phase:**

1. **spec-write** — The most critical agent. All downstream agents consume its output. Build first, test with hand-crafted inputs (mock intent.json + scan results). Verify output matches the locked spec JSON schema exactly.

2. **spec-review** — Build second. Test by feeding it known-good and known-bad specs. Verify Phase 1 catches ambiguity and gaps in bad specs, and Phase 2 catches compound criteria, untestable criteria, and external state dependencies. Verify it passes clean specs.

3. **spec-derive-intent** — Build third. Test with real scan output from Read Truth against the actual codebase. Verify it produces valid intent.json that spec-write can consume.

4. **run-spec-refinement** — Build last in this phase. Wire up all three agents. Test the spec cycle by feeding it a change that requires revision (spec-review should fail first pass, spec-write should fix it on second pass).

**Why this order:** spec-write's output is the central contract. Building it first lets you validate the spec schema in practice, not just on paper. spec-review is its quality gate — build it before the orchestrator so you can test it in isolation. spec-derive-intent comes after spec-write because spec-write can be tested with hand-crafted intent; spec-derive-intent needs real scan output and is better tested against the actual codebase.

### Phase 2: Implementation Core

**Build order within phase:**

5. **impl-write-tests** — Reads spec.json (already validated in Phase 1). Test by feeding it a known-good spec and verifying it produces test files that fail.

6. **impl-write-code** — Reads spec + test files. Test by feeding it a spec + failing tests and verifying it produces code that passes the tests.

7. **run-review-chain** — Build the orchestrator shell first, then the reviewers:
   - 7a. **review-scope** — Test with a diff that matches spec scope and one that doesn't.
   - 7b. **review-criteria-eval** — Test with a diff that satisfies all criteria and one that misses a criterion.
   - 7c. Wire into run-review-chain. Test fail-fast behavior and retry routing.

8. **git-tool** — Test all three modes independently. Branch creation, commit with derived message, PR opening with spec summary.

9. **run-implementation** — Wire up impl-write-tests → impl-write-code → run-review-chain → git-tool. Test the full TDD cycle on a real change.

**Why this order:** impl-write-tests and impl-write-code are the TDD core — they must work before the review chain has anything to review. Reviewers need real diffs to test against, which requires impl-write-code to be working. git-tool is mechanical and can be tested independently at any point but isn't needed until run-implementation wires everything together.

### Phase 3: Build Verification + Integration

10. **build-check** (bash script) — Write the script that detects the project's toolchain and runs the appropriate build, lint, typecheck, and test commands, captures exit codes and error output, and writes `build-check.json`. See `.claude/scripts/build-check.sh` for supported toolchains and `.strut/build.json` for override configuration. Test against a branch with passing code and one with deliberate errors.

11. **build-error-cleanup** — Test with specific error types: type errors, lint failures, test failures.

12. **run-build-check** — Wire up and test the retry cycle.

13. **run-process-change** — The phase orchestrator. Wire up run-spec-refinement → gate → run-implementation → run-build-check → git-tool (pr) → gate. Test resume behavior at both gates. Test the PR rejection path (pre-build decision #4).

### Phase 4: Delivery Loop End-to-End

14. **run-strut** — The top-level entry point. Wire up run-read-truth → run-process-change (two phases). Test end-to-end on a real change through the full delivery loop: classify → spec → tests → impl-write-code → review → build → PR → merge. Update Truth is not wired yet — run-strut returns after merge.

**Why run-strut before knowledge capture:** The delivery loop (Read Truth → Process Change) is the critical path. Proving it works end-to-end before adding Update Truth means you have a functioning pipeline sooner. Knowledge capture adds value but isn't load-bearing — nothing breaks without it.

### Phase 5: Knowledge Capture

15. **update-capture** — Test with a completed pipeline state (all result files populated). Verify it reads the right inputs and produces reasonable proposals.

16. **run-update-truth** — Wire up and test.

17. **Wire run-update-truth into run-strut** — Add the third phase dispatch. Test end-to-end with Update Truth included.

### Testing Strategy Per Component

For each agent: test without directives first (observe natural behavior), then add directives for observed failures (reactive method from universal constraints). The TDD-for-agents pattern from post-architecture-reference: run the agent without the directive, observe the failure, add the directive, verify the failure stops.

For each orchestrator: test dispatch and routing logic. Verify it reads status correctly, routes to the right next step, and handles failures by stopping (not improvising).

---

## 7. Deferred Components

Components designed into the architecture with explicit plug-in points, but not yet built. Built plugins graduate to "Trust ON Plugin" or "Decompose ON Plugin" subsections adjacent to the main sections they augment (see Section 1).

### Modifier-activated components (built)

**Per-task loop in run-implementation** — Activated by decompose ON. The orchestrator reads `classification.json.modifiers.decompose` and `spec.json.tasks[]` to iterate Steps 4–8 per task. Writes `.pipeline/implementation/active-task.json` before each task cycle so agents resolve the active task id. Retry budget resets per task. Context compaction between tasks. Standard path has one task — loop executes once, behavior unchanged.

**Decomposition validation in spec-review** — Activated by decompose ON. Phase 3 checks: context-fit, eval-fit, merge-fit, dependency-fit.

**Adversarial spec attack** — Activated by guarded-decompose (both trust ON and decompose ON). Human activity in a separate session. Pipeline pauses at run-process-change Step 6b.

**Task 1 human gate** — Activated by decompose ON. run-implementation returns `status: "blocked"` with `gate: "task_1"` after task 1's commit. run-process-change handles the gate (Step 7b), writes `process-change-state.json` with `gate: "task_1"` and `start_task`, and pauses. On resume, Step 4 routes to Step 7 which re-dispatches run-implementation with the `start_task` arg. Same gate mechanism as spec approval and PR review.

**Step mode** (`--step` flag) — Implemented across all orchestrators. When `--step` appears in `$ARGUMENTS`, run-strut writes `.pipeline/step-mode`. Every orchestrator checks for this flag file after each dispatch. On pause, run-process-change writes `gate: "step_pause"` blocked state with a `next` field for resume routing; sub-orchestrators (run-implementation, run-review-chain, run-build-check, run-spec-refinement, run-read-truth) use a simpler stop-on-abort pattern. The flag is per-invocation — omitting `--step` on the next invocation removes the flag file. run-strut cleans up the flag after Update Truth completes.

### Operational features (designed, build after pipeline runs end-to-end)

**Phase entry** (`--from [phase]` flag) — Plug-in point: run-process-change. Skips early sub-orchestrators and checks that prerequisite files exist. Entry points map to sub-orchestrator boundaries: `spec-refinement`, `implementation`, `build-check`, `pr`. Trigger: when you want to skip phases you've already handled manually.

**passed_with_concerns status** — Plug-in point: reviewer agents (review-scope, review-criteria-eval, review-security). A middle ground between pass and fail — non-blocking warnings that surface at human gates. Trigger: when binary pass/fail proves too coarse during testing.

**Spec visualization at approval gate** — An on-demand tool (script or Claude.ai prompt, not a pipeline agent) that reads `spec.json` and scan results to generate a visual showing which files are modified, which layers are touched, and how data flows between them. Not worth running on every change — useful when the human finds a spec hard to understand from the JSON alone. Trigger: when you find yourself struggling to understand a change at the spec approval gate.

### Extensibility (post-MVP, if open-sourcing)

**Registry-based orchestrator dispatch** — Refactor orchestrators from hardcoded dispatch sequences to reading from registry files (`.claude/registries/[orchestrator].json`). Enables third parties to add agents by dropping an agent file and adding a registry entry, without editing orchestrator code. The current architecture doesn't block this — agents are dispatch-agnostic and the refactor is entirely in orchestrator skills.

**Agent manifests** — Small JSON files per agent declaring inputs, outputs, status values, and model. The information already exists in this document's file contract table — manifests make it machine-readable. Enables dependency validation (orchestrator checks that an agent's required inputs exist before dispatching) and self-documenting plugin distribution.

### Post-MVP components (designed, build when scale demands)

**Team scaling protocol** — Detailed activation points from old architecture review. Trigger: hiring or collaborating.

**Evolution Engine** — Background pattern extraction, drift detection, fitness-based re-evolution. Trigger: codebase large enough that patterns emerge and drift matters.

**Test Wisdom directory** — Meta-knowledge about the test suite. Trigger: test suite large enough that you're losing track of trustworthiness.

---

## Component Summary

### Standard Path Components (build these)

| # | Component | Type | Model | Location |
|---|-----------|------|-------|----------|
| 1 | run-strut | Skill (entry point) | session | `.claude/skills/run-strut/SKILL.md` |
| 2 | run-read-truth | Skill (phase orch.) | session | `.claude/skills/run-read-truth/SKILL.md` ★ built |
| 3 | run-process-change | Skill (phase orch.) | session | `.claude/skills/run-process-change/SKILL.md` |
| 4 | run-spec-refinement | Skill (sub-orch.) | session | `.claude/skills/run-spec-refinement/SKILL.md` |
| 5 | run-implementation | Skill (sub-orch.) | session | `.claude/skills/run-implementation/SKILL.md` |
| 6 | run-review-chain | Skill (sub-orch.) | session | `.claude/skills/run-review-chain/SKILL.md` |
| 7 | run-build-check | Skill (sub-orch.) | session | `.claude/skills/run-build-check/SKILL.md` |
| 8 | run-update-truth | Skill (phase orch.) | session | `.claude/skills/run-update-truth/SKILL.md` |
| 9 | spec-derive-intent | Agent (worker) | Sonnet | `.claude/agents/spec-derive-intent.md` |
| 10 | spec-write | Agent (worker) | Sonnet | `.claude/agents/spec-write.md` |
| 11 | spec-review | Agent (worker) | Sonnet | `.claude/agents/spec-review.md` |
| 12 | git-tool | Agent (worker) | Haiku | `.claude/agents/git-tool.md` |
| 13 | impl-write-tests | Agent (worker) | Sonnet | `.claude/agents/impl-write-tests.md` |
| 14 | impl-write-code | Agent (worker) | Sonnet | `.claude/agents/impl-write-code.md` |
| 15 | review-scope | Agent (worker) | Sonnet | `.claude/agents/review-scope.md` |
| 16 | review-criteria-eval | Agent (worker) | Sonnet | `.claude/agents/review-criteria-eval.md` |
| 17 | build-check | Bash script | n/a | `.claude/scripts/build-check.sh` |
| 18 | build-error-cleanup | Agent (worker) | Sonnet | `.claude/agents/build-error-cleanup.md` |
| 19 | update-capture | Agent (worker) | Sonnet | `.claude/agents/update-capture.md` |

### Trust ON Additions (build when first trust-sensitive change arises)

| # | Component | Type | Model | Location |
|---|-----------|------|-------|----------|
| 20 | review-security | Agent (worker) | Opus | `.claude/agents/review-security.md` |
| 21 | impl-describe-flow | Agent (worker) | Sonnet | `.claude/agents/impl-describe-flow.md` |

### Total: 19 standard-path components (8 skills + 10 agents + 1 bash script) + 2 trust-ON agents

---

## Design Principles (carried from methodology, applied here)

**One pipeline, variable intensity.** This document defines the base. Trust and decompose add to it; they never change the sequence.

**Spec before code.** Nothing enters implementation without spec.json existing and a human approving it.

**Tests before implementation.** impl-write-tests runs before impl-write-code. Structural enforcement: impl-write-code reads test files as input; run-review-chain checks criteria_coverage.

**Human gates, not human approvals.** The pipeline runs automatically between gates. Humans intervene at gates — they don't approve each step.

**Resume from file state.** Every gate writes `process-change-state.json`. Every resume reads it. The pipeline survives hours or days of human pause.

**Orchestration as skills, work as agents.** Two-layer model, no exceptions. Skills dispatch and route. Agents do isolated work.

**Sub-orchestrator context isolation.** Each sub-orchestrator manages its own dispatch cycle with fresh context budget. run-process-change delegates multi-step sequences to sub-orchestrators but may dispatch standalone agents directly for single-step operations (e.g., git-tool for PR creation, impl-describe-flow for trust ON).

**Retry budgets are scoped per invocation.** run-spec-refinement: max 5 iterations. run-review-chain: max 3 retries. run-build-check: max 3 attempts. No parent retries a sub-orchestrator — it escalates to human.

**Start minimal, add based on observed failures.** Each agent starts with role, inputs, output schema, and core task. Directives are added when testing reveals specific failure modes. Three pipeline-wide techniques apply to every agent from the start: "Thinking X? STOP." format, Explore agent ban, "write file, stop" failure behavior.

**Self-audit where no deterministic verifier exists.** Agents whose output is checked by test execution (impl-write-code) don't need a probabilistic self-audit — the tests are the audit. Agents whose output feeds only probabilistic reviewers or no reviewer at all (spec-write, impl-write-tests) benefit from a same-context self-audit step between planning and output.
