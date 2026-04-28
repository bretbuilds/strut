# STRUT

**S**ource-anchored, **T**est-driven, **R**esearch-grounded, **U**ser-gated, **T**raceable — a spec-first, TDD-enforced development pipeline built on Claude Code's skill/agent architecture.

## Why this exists

AI coding tools make it easy to generate code and hard to verify it. The bottleneck has moved from writing to specifying, reviewing, and testing, but most workflows still optimize for speed of generation. STRUT structures the process around the parts that actually break.

Each letter represents a design principle:

- **Source-anchored.** Every pipeline run starts by scanning your actual codebase. Agents plan from real file paths and existing patterns, not assumptions.
- **Test-driven.** Tests are written before implementation, and they're the permanent asset. Code is disposable; the test suite is what survives.
- **Research-grounded.** Every structural decision cites its source: peer-reviewed papers, industry reports, or explicit design judgment. Nothing is vibes-based. See [`architectural-decisions.md`](docs/strut-architecture/architectural-decisions.md) for the full rationale.
- **User-gated.** The pipeline pauses at two high-leverage points (spec approval and PR review) where human judgment converts into the most protection. Automated review runs first so you review pre-filtered output, not raw diffs.
- **Traceable.** Agents communicate through file contracts in `.pipeline/`, not shared context. Every decision has a paper trail from scan evidence → classification → spec → tests → implementation → review.

## How it works

STRUT is a change-processing pipeline. You describe a change; the pipeline scans your codebase, classifies the change by risk, writes a spec, gets your approval, implements with tests first, runs an automated review chain, and opens a PR. You're prompted at two gates: spec approval (before implementation) and PR review (before merge).

The pipeline has three phases, **Read Truth** (scan the codebase, classify the change), **Process Change** (spec → approve → test → implement → review → build), and **Update Truth** (capture knowledge for the next run), connected by file contracts in `.pipeline/` that keep agents isolated from each other's context.

A classification system scales ceremony to risk. Two independent modifiers, **trust** (fires when the change touches auth, security, schema, or data boundaries) and **decompose** (fires when the change crosses 2+ architectural boundaries), add or remove pipeline steps based on what the scan finds, not on human guesswork.

## What STRUT is and isn't

STRUT is not a code generator, a framework, or a language-specific toolkit. It's an orchestration layer that runs your build, lint, typecheck, and test commands through the Read Truth → Process Change → Update Truth cycle described above, with gates at the points where judgment matters.

**What STRUT provides:**

- A pipeline of orchestrator skills and worker agents under `.claude/`
- A classification system (trust / decompose modifiers) that scales ceremony to risk
- Rules files that govern both session-level Claude behavior and pipeline execution
- A file contract system in `.pipeline/` that lets agents communicate without contaminating each other's context

**What STRUT doesn't provide:**

- Opinions about your language, framework, or test runner
- Pre-configured commands for a specific stack
- A database schema, auth system, or any application code

---

## Prerequisites

- Claude Code installed (`.claude/rules/` auto-loading requires v2.0.64 or later)
- Project under version control with a clean branching workflow
- A working build/lint/test pipeline in your project. STRUT orchestrates these, it doesn't provide them
- Familiarity with your project's data-layer paths (for scoping `database.md` if you use it)

---

## Getting started

Integration splits into three groups: mechanical setup Claude can do for you, domain setup that requires your knowledge, and ongoing practices that happen through normal use.

### Section A: Delegate to Claude

These are mechanical steps. Claude can do them all in one pass given a stack description. A reasonable first prompt: *"My stack is [X]. Do the Section A integration steps from the STRUT README. Flag anything you're uncertain about."*

**A1. Fill in `CLAUDE.md` build commands.** Replace the commented-out placeholders with your project's actual commands. These are what `scripts/build-check.sh` will invoke.

**A2. Adapt `scripts/build-check.sh`.** The script runs your build/lint/typecheck/test commands and writes a result JSON to `.pipeline/build-check/build-check.json`. The template ships with placeholder commands; update them to match your project. This is the one file in the architecture that is deliberately stack-specific.

**A3. Update `architecture.md` directory tree.** The template assumes a generic layout (`app/lib/`, `app/components/`). Update the tree and the shared-logic rule (rule 2) to match your project's actual structure. If your project doesn't have an `app/` directory or doesn't separate shared logic/UI that way, Claude can detect the real layout from your project and rewrite accordingly.

**A4. Scope or flag `database.md`.** If your stack matches the file's SQL + multi-tenant + RLS baseline (Postgres with Supabase, Prisma, Drizzle, etc.), Claude can uncomment the `globs:` frontmatter and set the paths to your actual data-layer directories. If your stack doesn't match (NoSQL, single-tenant, no RLS), Claude should flag the file as needing replacement rather than silently converting it, since replacing these rules is a judgment call you should review.

**A5. Add your stack's commands to `.claude/settings.json`.** The template ships with git, file-manipulation, and general shell commands pre-authorized in the `allow` list, but not language-specific commands. Claude needs to add entries for your build, lint, typecheck, test, and package-manager commands so those don't interrupt the pipeline with permission prompts. Examples:

| Stack | Entries to add to `allow` |
|-------|---------------------------|
| npm | `Bash(npm run build:*)`, `Bash(npm run lint:*)`, `Bash(npm run typecheck:*)`, `Bash(npm test:*)`, `Bash(npm install:*)`, `Bash(npx:*)`, `Bash(node:*)` |
| Python | `Bash(python:*)`, `Bash(python3:*)`, `Bash(pip install:*)`, `Bash(pytest:*)`, `Bash(mypy:*)`, `Bash(ruff:*)` |
| Rust | `Bash(cargo build:*)`, `Bash(cargo test:*)`, `Bash(cargo clippy:*)`, `Bash(cargo check:*)` |
| Go | `Bash(go build:*)`, `Bash(go test:*)`, `Bash(go vet:*)`, `Bash(gofmt:*)` |

**A6. Add dependency-manifest protection to `.claude/settings.json`.** Architecture rule 9 says "no new dependencies without approval." Enforce this mechanically by adding the relevant manifest file(s) to the `ask` list so Claude has to confirm before editing them. Examples:

| Stack | Entries to add to `ask` |
|-------|-------------------------|
| npm | `Edit(package.json)`, `Edit(package-lock.json)`, `Bash(npm publish:*)` |
| Python | `Edit(pyproject.toml)`, `Edit(requirements.txt)`, `Bash(twine upload:*)`, `Bash(poetry publish:*)` |
| Rust | `Edit(Cargo.toml)`, `Bash(cargo publish:*)` |
| Go | `Edit(go.mod)` |

**A7. Add language-specific code conventions to `operating-rules.md`.** The file has a TODO block under "Code Generation" for language-specific rules. Claude can generate a reasonable starting set based on your language (destructuring depth for JS/TS, docstring style for Python, error-type conventions for Rust, etc.). Review these; coding conventions are opinionated and Claude is guessing at your preferences.

**A8. Uncomment your stack's block in `.gitignore`.** The universal section (environment variables, OS files, editor files, logs, coverage, pipeline state) is active by default. Stack-specific entries (Node, Python, Rust, Go) ship commented out; Claude should uncomment the block matching your stack and delete the others. If skipped, build artifacts and dependency directories will start getting committed.

**What happens if you skip Section A:** The pipeline won't run. These steps are load-bearing for basic operation. Claude doing them takes minutes; leaving them undone breaks the pipeline at the first change.

### Section B: Your domain knowledge

These steps encode knowledge Claude doesn't have. Claude can scaffold but not fill in.

**B1. Populate `security.md` MUST NEVER section.** Each entry here becomes a negative test under trust ON. Claude can suggest generic invariants ("users from one org must not access another org's data") but the load-bearing entries come from your understanding of what breaks if violated: *"payment records must never be modified after the settlement timestamp,"* *"audit logs must never lose entries on partial failure."* Wrong MUST NEVERs are worse than missing ones: they become tests that either never fire (useless) or block legitimate behavior (harmful).

Format: `MUST NEVER: [constraint] — added [date] from [source]`. When trust ON, `spec-derive-intent` reads this section to populate the spec's `must_never[]` array; the scan reads it for trust-sensitive definitions.

Entries also arrive automatically over time via the self-improving rules cycle: the scan outputs a `rules_gaps` entry when it detects a risk signal without a matching rule; post-merge, `update-capture` proposes specific rule text for you to review and add.

**What happens if you skip this:** Trust ON changes run without negative tests for your specific invariants. The scan and reviewers still catch general trust violations, but project-specific invariants go unprotected. Not a pipeline breaker, but meaningfully weakens the safety net.

**B2. Populate `docs/user-context/` (optional but recommended).** This folder is read by `spec-derive-intent` before spec writing. It enriches spec quality by giving the agent access to product decisions, user expectations, and domain vocabulary that aren't obvious from the code alone.

The folder ships empty (contains only `docs/user-context/README.md`). You populate it yourself, in two phases:

- **Initial seeding during integration.** Create a few files covering your major product areas, drawing from whatever notes, docs, or wiki pages already exist in your organization. A typical starting point is 3–5 files: one per product area with its key decisions, a glossary for domain vocabulary, a trust-invariants file for expectations that go beyond code-level rules. You can also start with zero files and add them reactively if you prefer.
- **Ongoing additions during normal use.** Every time you clarify something at the spec approval gate that `spec-derive-intent` should have known, like "published updates are immutable after 24 hours" or "our 'customer' means account holder, not end user," that clarification is a candidate for a new context file.

What belongs: product decisions, trust invariants beyond code-level rules, user expectations, domain vocabulary the AI might misinterpret.

What doesn't belong: code documentation (the scan reads your code directly), API references, deployment config, changelogs.

Any readable structure works. Organize by feature area, user segment, team ownership, or whatever makes sense; the scan reads the folder's contents, not a prescribed schema.

**What happens if you skip this:** `spec-derive-intent` still runs but derives intent from scan evidence alone. Specs are thinner and less accurate to your product context. Mismatches get caught at the spec approval gate, but approval takes longer. If specs keep failing review for "missing criteria" or "unclear intent," populating this folder is usually the fix.

### Section C: Ongoing

These happen naturally as you use the pipeline.

**C1. Seed project-specific rules as they emerge.** Don't try to front-load every rule. The self-improving cycle will surface gaps through normal pipeline runs. Add rules when you observe a specific failure, not in anticipation. Areas that commonly accumulate rules: commit message format, branch naming, PR title conventions, issue/ticket reference patterns.

**C2. Populate `docs/project/decision-log.md` as you make non-obvious decisions.** Technology choices, architectural patterns, scope boundaries, deferred work. Entries also arrive from `update-capture` proposals after pipeline runs. The log is append-only; if a decision is superseded, add a new entry referencing the old one.

**C3. Update `docs/project/system-map.md` as architecture evolves.** Data flow, service boundaries, integration points, trust boundaries. Unlike the decision log, this file is edited in place to reflect current state. The scan reads it for grounding when planning changes. Start with whatever exists; fill in sections as they become relevant.

---

## Running the pipeline

After integration, invoke the pipeline with:

```
/run-strut <describe the change you want>
```

The pipeline scans your codebase, classifies the change, and walks through: spec refinement → spec approval gate → implementation (tests first, then code) → review chain → build check → PR. You'll be prompted at two gates: spec approval (before implementation starts) and PR review (before merge).

### Step mode

Add `--step` to pause after every agent/skill dispatch:

```
/run-strut --step <describe the change you want>
```

The pipeline will stop after each step, showing the completed agent, its output file, and the next step. At each pause you can type `continue` to proceed or `abort` to stop the pipeline.

Step mode is useful for your first few pipeline runs, when you want to inspect each agent's output before the next one starts. The flag is per-invocation; omitting `--step` on a resume disables it. On abort, re-invoke with `--step` to resume from the last checkpoint.

For the full pipeline architecture, see `docs/strut-architecture/core-path-architecture.md`.

---

## The modifier system

Every pipelined change is classified by `truth-classify` based on scan evidence. Classification produces two independent modifiers:

**Trust ON** triggers if the scan detects any of: auth, RLS, schema changes, security boundaries, data immutability, encryption, multi-tenant isolation. Adds MUST NEVER collection, negative criteria, security-review (Opus), describe-flow, mandatory knowledge capture.

**Decompose ON** triggers if the change crosses 2+ architectural boundaries (UI / server / database). Adds task breakdown (up to 5 tasks), per-task TDD loop, and a gate after task 1 to verify the approach before remaining tasks proceed.

Both modifiers are independent. Combinations: standard (both OFF), trust-only, decompose-only, guarded-decompose (both ON, adds adversarial spec review).

**Verifying classification works on your codebase:** on the first few changes, check that `classification.json` in `.pipeline/` matches what you'd expect. If trust-sensitive files (auth, migrations, etc.) aren't triggering trust ON, the scan isn't recognizing your project's patterns, and you may need to add rules that help it identify trust-sensitive code.

For worked examples of each classification path, see `docs/strut-architecture/modifiers/`.

---

## Extending STRUT

You can build your own skills and agents to extend the pipeline:

- **Templates:** `docs/contributing/templates/` has blank templates for agents, skills, and specs. Copy one to start a new component.
- **Testing:** `docs/contributing/testing/` has a dual-model test harness that generates and runs tests under both Sonnet and Opus. Run `bash docs/contributing/testing/run-tests.sh <component-name>` to validate a new component.
- **Architecture reference:** `docs/strut-architecture/` has the full design rationale, constraint model, and research citations behind the pipeline's structure.

**Modifier-activated plugins.** Not every component needs to run on every change. You can build plugins that activate only when a specific modifier fires; the agent reads `classification.json` for the modifier state and the orchestrator's step sequence includes a conditional guard (`if trust_on is false, skip`). The existing trust ON plugins, `review-security` (Opus security audit in the review chain) and `impl-describe-flow` (data flow description before PR creation), are worked examples. See their agent files and the `#### Trust ON Plugin:` subsections in the architecture doc for the pattern. Unbuilt plugin points are listed in Section 7 of the architecture doc.

---

## How rules files load

Claude Code auto-loads all markdown files in `.claude/rules/` at session start. By default, every rule in every file is in context for every session.

Two mechanisms reduce this load:

**Frontmatter scoping.** Rules files can include a `globs:` frontmatter block listing path patterns. The file then loads only when Claude is working with matching files. `database.md` ships configured for this (commented out until you set your paths). `pipeline.md` is already scoped to `.claude/skills/**`, `.claude/agents/**`, and `scripts/**`.

**Important:** use `globs:` (not the documented `paths:` syntax). The `paths:` field has known YAML parsing issues in Claude Code; it silently fails to match. Verify your scoping actually works by running `/context` in a session and checking which rules files appear in "Memory files."

**File roles in the template:**

| File | Load scope | Purpose |
|------|-----------|---------|
| `CLAUDE.md` | Every session | Project identity, build commands, modifier table, pointer to architecture doc |
| `architecture.md` | Global | Directory structure, naming, design principles |
| `methodology.md` | Global | Classification, TDD, review chain, spec cycle, anti-rationalization |
| `operating-rules.md` | Global | Build/test/CI requirements, scope discipline, error recovery |
| `security.md` | Global | Trust invariants, RLS rules, MUST NEVER constraints |
| `database.md` | Scope after setup | Data-layer conventions (SQL + multi-tenant + RLS baseline) |
| `pipeline.md` | Scoped (pre-set) | Skill/agent authoring constraints, file contracts, pipeline execution |

---

## Adapting the SQL + multi-tenant + RLS baseline

Two files assume this common backend shape: `database.md` and `security.md` (RLS section).

**If your stack matches the baseline:** use the files as-is, just scope `database.md` (Section A) and populate `security.md`'s MUST NEVER section (Section B).

**If your stack differs:**
- Replace `database.md` with rules appropriate to your data layer (NoSQL access patterns, single-tenant query conventions, etc.)
- Replace `security.md`'s RLS section with your equivalent authorization boundary (document-level access rules, row-level filters in the application layer, whatever your stack uses). Keep the Authentication, Data Immutability, Encryption and Secrets, and MUST NEVER sections, as those are stack-agnostic.

---

## Common pitfalls

**Stale `.pipeline/` files.** The pipeline cleans its own directories between runs, but if you manually interrupt a run and start a different change without invoking `/run-strut`, old files can persist. If you see agents reading unexpected content, check `.pipeline/` and clean it manually (`rm -rf .pipeline/spec-refinement .pipeline/implementation .pipeline/build-check .pipeline/update-truth`).

**Frontmatter scoping silently not working.** Both bugs are documented: `paths:` syntax fails to parse, and occasionally scoped rules load globally anyway. Always verify with `/context` after setting up scoping. If a scoped file doesn't appear when expected, try the `globs:` syntax and restart the session.

**Assuming the template's directory conventions match yours.** `architecture.md` rule 2 references `app/lib/` and `app/components/`. If your project uses `src/` or `packages/` or a different structure, update the rule, otherwise Claude will try to put files in directories that don't exist.

**Skipping `docs/user-context/` setup and wondering why specs are thin.** `spec-derive-intent` works without it, but specs derived from scan evidence alone tend to miss product context. If specs keep failing review for "missing criteria" or "unclear intent," populating `docs/user-context/` is usually the fix.

**Treating classification as negotiable.** Session Claude doesn't classify; `truth-classify` does, based on scan evidence. If a classification feels wrong, override manually at the gate or add a rule that helps the scan make a better call next time.

---

## Further reading

| Doc | What it covers |
|-----|---------------|
| `docs/strut-architecture/core-path-architecture.md` | Full pipeline: phases, agents, skills, file contracts, dispatch sequences |
| `docs/strut-architecture/architectural-decisions.md` | Why each load-bearing choice was made, with research citations |
| `docs/strut-architecture/modifiers/` | Worked examples of all four classification paths |
| `docs/contributing/` | Templates and testing tools for building new pipeline components |