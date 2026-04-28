# Architecture Rules

## Project Structure

1. Follow the established directory structure. Do not create new top-level directories without human approval.

```
.claude/
  skills/          # Orchestrator skills (dispatch + route, shared context)
  agents/          # Worker agents (isolated tasks, fresh context per dispatch)
  rules/           # Behavioral rules (loaded by session or by path scope)
.pipeline/         # File contract layer — all inter-agent communication
.specs/            # Archived specs post-merge (historical reference)
docs/
  context/         # Optional business context for spec-derive-intent enrichment
  core-path-architecture.md
.claude/
  scripts/         # Bash scripts (build-check, utilities)
app/               # Application code
  lib/             # Shared logic
  components/      # Shared UI
```

2. Shared logic goes in `app/lib/`. Shared UI goes in `app/components/`. Do not duplicate logic across routes.

## Component Patterns

<!-- TODO: Add project-specific component patterns (registries, orchestrators, etc.) -->
3. Server components are the default. Use client components only when interactivity requires it.
4. Server actions handle all data mutations. No direct database calls from components.
5. Each component should have one job. If a function does two unrelated things, split it.

## Naming Conventions

<!-- TODO: Add project-specific naming conventions (CSS prefix, vocabulary, etc.) -->
6. Files use kebab-case. Components use PascalCase. Functions use camelCase.
7. Database columns use snake_case.
8. Documentation and config files use kebab-case. Only files required by external tools keep SCREAMING_CASE (CLAUDE.md, SKILL.md, README.md).

## Dependencies

9. No new dependencies without human approval. Check if existing dependencies cover the use case first.

## Design Principles

10. Fail explicitly — when something goes wrong, handle it visibly. No silent failures, no swallowed errors. Claude Code tends to generate optimistic code that ignores error paths.
11. Single source of truth — each piece of data lives in one place. If it can be derived, derive it rather than storing a second copy. The working codebase + tests + knowledge substrate (rules, decisions, system map) are the source of truth. Specs are transient — consumed on merge, archived in `.specs/`.
12. Tests are the permanent asset, code is disposable — any implementation can be regenerated if the tests exist to verify correctness. Do not treat current code as precious.