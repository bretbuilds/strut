# System Map

Current architecture of this project. Edited in place as the architecture evolves — not append-only like `decision-log.md`, because outdated architecture diagrams mislead.

This file captures *how your project is wired*, distinct from `docs/strut-architecture/architectural-decisions.md` which captures *why STRUT is built the way it is*.

## Purpose

The system map is a quick-reference overview of the project's structural shape. `update-capture` may propose updates to this file after architectural changes; the human reviews and applies. The scan can read it for grounding when planning changes.

## Rules

1. Edit in place. This file reflects the current state, not history. Architectural history lives in `decision-log.md`.
2. Keep it concise. The codebase is the source of truth for structure; this file is a map, not a replacement.
3. Update when architecture changes. A new service boundary, a new integration, a data flow change — these update the map.
4. Empty sections stay as headings. Adopters populate what exists; placeholder headings signal what to add when the time comes.

## Sections

### Data flow

<!-- How data moves through the system. User action → server → database → response.
     For a new project, this is often one or two sentences. Grows as the system grows. -->

### Service boundaries

<!-- What are the logical services or modules? Where are the seams?
     For a monolith, this may describe internal module boundaries rather than network services. -->

### Integration points

<!-- External systems the project depends on or exposes: auth providers, payment processors,
     APIs consumed, APIs exposed, queues, caches, third-party data sources. -->

### Trust boundaries

<!-- Where does untrusted input cross into trusted execution?
     Authentication boundaries, tenant boundaries, privilege escalation points.
     This section informs `spec-derive-intent`'s MUST NEVER population under trust ON. -->

## If this file is empty

Early in a project, most sections will be empty. That's expected. As architecture decisions are made, populate the corresponding section. `update-capture` will also propose updates here after architectural changes — review and apply.