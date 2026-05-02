# STRUT

**S**ource-anchored, **T**est-driven, **R**esearch-grounded, **U**ser-gated, **T**raceable — a spec-first, TDD-enforced development pipeline built on Claude Code's skill/agent architecture.

## Why this exists

AI coding tools make it easy to generate code and hard to verify it. The bottleneck has moved from writing to specifying, reviewing, and testing, but most workflows still optimize for speed of generation. STRUT structures the process around the parts that actually break.

Each letter represents a design principle:

- **Source-anchored.** Every pipeline run starts by scanning your actual codebase. Agents plan from real file paths and existing patterns, not assumptions.
- **Test-driven.** Tests are written before implementation, and they're the permanent asset. Code is disposable; the test suite is what survives.
- **Research-grounded.** Every structural decision cites its source: peer-reviewed papers, industry reports, or explicit design judgment. Nothing is vibes-based. See [`architectural-decisions.md`](docs/strut-architecture/architectural-decisions.md) for the full rationale.
- **User-gated.** The pipeline pauses at two high-leverage points (spec approval and PR review) where human judgment converts into the most protection. Automated review runs first so you review pre-filtered output, not raw diffs.
- **Traceable.** Agents communicate through file contracts in `.strut-pipeline/`, not shared context. Every decision has a paper trail from scan evidence → classification → spec → tests → implementation → review.

## How it works

STRUT is a change-processing pipeline. You describe a change; the pipeline scans your codebase, classifies the change by risk, writes a spec, gets your approval, implements with tests first, runs an automated review chain, and opens a PR. You're prompted at two gates: spec approval (before implementation) and PR review (before merge).

The pipeline has three phases, **Read Truth** (scan the codebase, classify the change), **Process Change** (spec → approve → test → implement → review → build), and **Update Truth** (capture knowledge for the next run), connected by file contracts in `.strut-pipeline/` that keep agents isolated from each other's context.

A classification system scales ceremony to risk. Two independent modifiers, **trust** (fires when the change touches auth, security, schema, or data boundaries) and **decompose** (fires when the change crosses 2+ architectural boundaries), add or remove pipeline steps based on what the scan finds, not on human guesswork.

[View the full pipeline diagram (interactive HTML)](docs/strut-architecture/visuals/strut-high-level-architecture.html)

## What STRUT is and isn't

STRUT is not a code generator, a framework, or a language-specific toolkit. It's an orchestration layer that runs your build, lint, typecheck, and test commands through the Read Truth → Process Change → Update Truth cycle described above, with gates at the points where judgment matters.

**What STRUT provides:**

- A pipeline of orchestrator skills and worker agents (installed to `.claude/` via plugin)
- A classification system (trust / decompose modifiers) that scales ceremony to risk
- Rules files that govern both session-level Claude behavior and pipeline execution
- A file contract system in `.strut-pipeline/` that lets agents communicate without contaminating each other's context

**What STRUT doesn't provide:**

- Opinions about your language, framework, or test runner
- Pre-configured commands for a specific stack
- A database schema, auth system, or any application code

---

## Prerequisites

- Claude Code installed (v2.0.64 or later)
- Project under version control with a clean branching workflow
- A working build/lint/test pipeline in your project. STRUT orchestrates these, it doesn't provide them

---

## Getting started

### Install

```
claude plugin add github:bretbuilds/strut
```

### Initialize your project

```
/strut:init
```

This analyzes your codebase and:
- Copies pipeline skills, agents, and scripts to `.claude/`
- Copies rules templates to `.claude/rules/strut-*.md`, filling TODO placeholders based on your detected stack (build commands, directory layout, language conventions)
- Merges STRUT permissions into `.claude/settings.json`
- Appends the STRUT block to your `CLAUDE.md`
- Creates `.strut-pipeline/` and `.strut-specs/` directories
- Writes `strut-manifest.json` tracking installed files
- Runs a health check on total constraint count

### Review what init filled in

Init handles the mechanical setup but flags items needing your judgment:

- **`.claude/rules/strut-security.md`** — Add your MUST NEVER constraints. These encode what breaks if violated (*"payment records must never be modified after settlement,"* *"audit logs must never lose entries on partial failure"*). Claude can't guess these; wrong MUST NEVERs are worse than missing ones. Format: `MUST NEVER: [constraint] — added [date] from [source]`.
- **`.claude/rules/strut-database.md`** — Verify the detected data-layer conventions match your stack. If you don't use SQL/RLS/multi-tenant, replace with your equivalent.
- **`docs/user-context/`** — Optional. Add product context (decisions, domain vocabulary, trust invariants) for richer specs. Start with zero files and add reactively, or seed 3–5 files covering major product areas.

Entries arrive automatically over time via the self-improving rules cycle: the scan outputs `rules_gaps` when it detects a risk signal without a matching rule; post-merge, `update-capture` proposes specific rule text for you to review.

### Run the pipeline

```
/run-strut add user avatar upload to the profile settings page
```

If invoked without a description, it prints usage instructions.

The pipeline scans your codebase, classifies the change, and walks through: spec refinement → spec approval gate → implementation (tests first, then code) → review chain → build check → PR. You're prompted at two gates: spec approval (before implementation starts) and PR review (before merge).

### Update

```
/strut:update
```

Pulls the latest plugin version and refreshes pipeline skills, agents, and scripts while preserving your customizations in rules files and settings.

### Health check

```
/strut:doctor
```

Checks constraint count, file integrity, scoping verification, and settings completeness.

### Ongoing

These happen naturally as you use the pipeline:

- **Seed project-specific rules as they emerge.** Don't front-load; the self-improving cycle surfaces gaps. Add rules when you observe a specific failure, not in anticipation.
- **Populate `docs/project/decision-log.md` as you make non-obvious decisions.** Technology choices, architectural patterns, scope boundaries. Entries also arrive from `update-capture` proposals after pipeline runs.
- **Update `docs/project/system-map.md` as architecture evolves.** Data flow, service boundaries, integration points, trust boundaries.

---

## Step mode

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

**Verifying classification works on your codebase:** on the first few changes, check that `classification.json` in `.strut-pipeline/` matches what you'd expect. If trust-sensitive files (auth, migrations, etc.) aren't triggering trust ON, the scan isn't recognizing your project's patterns, and you may need to add rules that help it identify trust-sensitive code.

For worked examples of each classification path, see `docs/strut-architecture/modifiers/`.

---

## Extending STRUT

[View the sub-orchestrator reference cards (interactive HTML)](docs/strut-architecture/visuals/strut-sub-orchestrator-reference-cards.html)

You can build your own skills and agents to extend the pipeline:

- **Templates:** `docs/contributing/templates/` has blank templates for agents, skills, and specs. Copy one to start a new component.
- **Testing:** `docs/contributing/testing/` has a dual-model test harness that generates and runs tests under both Sonnet and Opus. Run `bash docs/contributing/testing/run-tests.sh <component-name>` to validate a new component.
- **Architecture reference:** `docs/strut-architecture/` has the full design rationale, constraint model, and research citations behind the pipeline's structure.

**Modifier-activated plugins.** Not every component needs to run on every change. You can build plugins that activate only when a specific modifier fires; the agent reads `classification.json` for the modifier state and the orchestrator's step sequence includes a conditional guard (`if trust_on is false, skip`). The existing trust ON plugins, `review-security` (Opus security audit in the review chain) and `impl-describe-flow` (data flow description before PR creation), are worked examples. See their agent files and the `#### Trust ON Plugin:` subsections in the architecture doc for the pattern. Unbuilt plugin points are listed in Section 7 of the architecture doc.

---

## How rules files load

Claude Code auto-loads all markdown files in `.claude/rules/` at session start. By default, every rule in every file is in context for every session.

Two mechanisms reduce this load:

**Frontmatter scoping.** Rules files can include a `globs:` frontmatter block listing path patterns. The file then loads only when Claude is working with matching files. `strut-database.md` ships configured for this. `strut-pipeline.md` is already scoped to `.claude/skills/**`, `.claude/agents/**`, and `scripts/**`.

**Important:** use `globs:` (not the documented `paths:` syntax). The `paths:` field has known YAML parsing issues in Claude Code; it silently fails to match. Verify your scoping actually works by running `/context` in a session and checking which rules files appear in "Memory files."

**File roles in the template:**

| File | Load scope | Purpose |
|------|-----------|---------|
| `CLAUDE.md` | Every session | Project identity, STRUT pipeline pointer |
| `strut-architecture.md` | Global | Directory structure, naming, design principles |
| `strut-methodology.md` | Pipeline runs only | Anti-rationalization rules for session Claude during pipeline execution |
| `strut-operating-rules.md` | Global | Build/test/CI requirements, scope discipline, error recovery |
| `strut-security.md` | Global | Trust invariants, RLS rules, MUST NEVER constraints |
| `strut-database.md` | Scope after setup | Data-layer conventions (SQL + multi-tenant + RLS baseline) |
| `strut-pipeline.md` | Scoped (pre-set) | Skill/agent authoring constraints, file contracts, pipeline execution |

### Why constraint count matters

Research shows that LLM compliance with instructions degrades as the number of loaded constraints increases — and the degradation is exponential, not linear.

Three findings establish this:

- **Curse of Instructions** (Harada et al., ICLR 2025): The probability of following ALL instructions drops as `success_all = success_individual^N`. Ten instructions at 99% per-instruction compliance gives 90% full compliance. Fifty gives 60%. The curve is steep.
- **AGENTIF** (Qi et al., NeurIPS 2025): Both constraint count AND total instruction length independently degrade compliance in agentic prompts. Long instructions with few constraints degrade. Short instructions with many constraints degrade. Both together degrade the most.
- **RECAST** (ICLR 2026): The degradation pattern holds across model generations, including the most recent at time of publication.

**What this means for your project:** Every rules file STRUT adds increases the total instruction length Claude processes each session. If your project already has rules files, the combined set competes for Claude's attention. STRUT is designed to minimize its footprint — pipeline-internal behavior is enforced by skills and agents (which run in isolated context), not by session-level rules. Only constraints that session Claude can uniquely violate remain as rules.

**If you notice degraded performance:** Run `/strut:doctor` to check your constraint count. Consider consolidating overlapping rules, removing rules that restate what your architecture already enforces, and using `globs:` scoping to limit which rules load in which contexts.

For the full constraint model and research citations, see `docs/strut-architecture/universal-constraints.md`.

---

## Adapting the SQL + multi-tenant + RLS baseline

Two files assume this common backend shape: `strut-database.md` and `strut-security.md` (RLS section). `/strut:init` detects your data layer and flags these for review if your stack doesn't match.

**If your stack matches the baseline:** use the files as-is and populate `strut-security.md`'s MUST NEVER section.

**If your stack differs:**
- Replace `strut-database.md` with rules appropriate to your data layer (NoSQL access patterns, single-tenant query conventions, etc.)
- Replace `strut-security.md`'s RLS section with your equivalent authorization boundary (document-level access rules, row-level filters in the application layer, whatever your stack uses). Keep the Authentication, Data Immutability, Encryption and Secrets, and MUST NEVER sections, as those are stack-agnostic.

---

## Common pitfalls

**Stale `.strut-pipeline/` files.** The pipeline cleans its own directories between runs, but if you manually interrupt a run and start a different change without invoking `/run-strut`, old files can persist. If you see agents reading unexpected content, check `.strut-pipeline/` and clean it manually (`rm -rf .strut-pipeline/spec-refinement .strut-pipeline/implementation .strut-pipeline/build-check .strut-pipeline/update-truth`).

**Frontmatter scoping silently not working.** Both bugs are documented: `paths:` syntax fails to parse, and occasionally scoped rules load globally anyway. Always verify with `/context` after setting up scoping. If a scoped file doesn't appear when expected, try the `globs:` syntax and restart the session.

**Assuming the template's directory conventions match yours.** `strut-architecture.md` rule 2 references `app/lib/` and `app/components/`. `/strut:init` detects your actual structure, but if it guessed wrong, update the rule — otherwise Claude will try to put files in directories that don't exist.

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