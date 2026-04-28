# CLAUDE.md

## Project

STRUT — A spec-first, TDD-enforced development pipeline built on Claude Code's skill/agent architecture.

**Platform:** Claude Code (skills as orchestrators, agents as workers)

**Session model:** Run the pipeline from a Sonnet session. Skills (orchestrators) inherit the session model and are designed for Sonnet. Agents pin their own models via frontmatter, so they run on the correct model regardless of session — but running on Opus wastes tokens on thin orchestration logic that doesn't benefit from it.

## Build Commands

<!-- A1: Replace with your project's actual commands -->
```bash
# npm run build    # production build
# npm run test     # test suite
```

## Development Methodology

This project uses a modifier-based spec-first + TDD methodology. Every pipelined change is scanned and classified by the pipeline before implementation.

| Modifier | When | Effect |
|----------|------|--------|
| Standard (both OFF) | Default when neither modifier triggers | Full pipeline: spec → tests → implement → review → build → PR |
| trust ON | Auth, RLS, schema, security, immutability, multi-tenant | Adds: MUST NEVER criteria, security-review (Opus), describe-flow, mandatory knowledge capture |
| decompose ON | 2+ architectural boundary crossings | Adds: task breakdown (≤5), per-task TDD loop, task 1 human gate |

**Classification authority:** The pipeline (truth-classify) determines modifiers from scan evidence. Session Claude displays the result. The human can override at the gate.

Full architecture: `docs/strut-architecture/core-path-architecture.md`

## Rules

All behavioral rules load automatically from `.claude/rules/`. Do not duplicate them here. If a rule needs to change, change it in the rules file.