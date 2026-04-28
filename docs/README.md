# docs/

Reference material for STRUT. What lives here, and when to read it.

## Subfolders

**`strut-architecture/`** — Everything about how and why STRUT is built: the core pipeline architecture, architectural decisions with research citations, the three-layer constraint model, pre-build decisions, deferred components, model limitations log, modifier system reference (with worked examples), and architecture visuals.

**`contributing/`** — Templates and tooling for building new pipeline components. Agent, skill, and spec templates in `templates/`. Dual-model test runner and assertion harness in `testing/`.

**`user-context/`** — Optional business context populated by the adopter. Read by `spec-derive-intent` before spec writing to enrich specs with product decisions, user expectations, and domain vocabulary that aren't obvious from the code.

**`project/`** — Project-specific state: decision log and system map. Files here grow as the project runs. Distinct from `strut-architecture/` (STRUT's own architecture) — this folder is about the adopter's project.
