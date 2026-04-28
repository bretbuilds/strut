# docs/strut-architecture/

Architectural decision artifacts and rationale. Read these when authoring new pipeline components, questioning an early design choice, or evaluating whether STRUT's approach fits your project.

## Files

**`architectural-decisions.md`** — Load-bearing architectural decisions mapped to their supporting evidence, with tier-labeled citations. The narrative answer to "why is STRUT shaped this way?" Organized by concern. Read this first if you're evaluating the architecture or considering changes.

**`research-index.md`** — Per-component index mapping each architectural element to its supporting sources. Organized by the structure of `core-path-architecture.md`. Complements `architectural-decisions.md` — same research, different access pattern. Use this when authoring or updating a specific component and you need the evidence base for that scope.

**`universal-constraints.md`** — The three-layer model (mechanical / architecture / directives) for where to enforce what when authoring agents and skills. The foundation reference for anyone writing a new pipeline component.

**`pre-build-decisions.md`** — Four locked decisions made before pipeline construction: the spec JSON schema, pipeline cleanup between runs, resume vs. new-run detection, and PR rejection loop-back paths. These shape multiple agents and are not meant to be revisited without strong reason.

**`tests-as-permanent-assets.md`** — The argument for why tests matter more than the code they verify in AI-driven development. Grounds the TDD enforcement decision and the "code is disposable" framing used elsewhere in the architecture.

**`deferred-components.md`** — Components designed but not yet built, each with the trigger condition under which it should be added. Consult this before building new features — the component you want may already be designed.

**`model-limitations-log.md`** — Observed LLM behavior issues from testing that affect pipeline operation. Each entry is grounded in testing, not speculation. Entries are removed when a model generation resolves them or an architectural change makes them irrelevant. Updated manually during agent development and testing.

**`core-path-architecture.md`** — The full pipeline architecture: phases, agents, skills, file contracts, modifier behavior, and dispatch sequences. The definitive reference for what STRUT does.

## Subfolders

**`modifiers/`** — Cheat sheet and worked examples for the trust/decompose modifier system. Covers all four execution paths with end-to-end scenarios.

**`visuals/`** — SVG architecture diagrams: high-level pipeline, sub-orchestrator reference cards, and decompose-ON comparison.