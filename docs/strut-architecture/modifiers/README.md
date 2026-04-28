# docs/strut-architecture/modifiers/

Reference material for the trust/decompose modifier system. The `truth-classify` agent does not read this folder at runtime — its classification rules are encoded in its own agent body. This folder exists for understanding the modifier system, debugging surprising classification results, and as behavior specs when building or testing the agent.

## Files

**`cheat-sheet.md`** — Trust triggers, decompose triggers, common-change patterns, edge cases, and guidance on when to skip the pipeline entirely. Scannable reference for decision-making; not a research document.

**`examples/`** — Worked scenarios showing the classification pipeline end-to-end for each execution path. Each file contains a change request, an abbreviated scan result, the expected classification output, and a prose explanation of why that path is correct.

| File | Path | Illustrates |
|------|------|-------------|
| `standard-css-fix.md` | standard | Zero risk signals, single UI-layer change |
| `standard-decompose-new-section.md` | standard-decompose | Zero risk signals, 2+ layer crossings |
| `guarded-rls-policy.md` | guarded | Multiple risk signals, single concern |
| `guarded-decompose-new-feature.md` | guarded-decompose | Risk signals + 2+ layer crossings |
| `edge-case.md` | guarded (from bug-fix framing) | Small change that fires trust from evidence, not intent |

## About the examples

These examples are drawn from a specific codebase (a multi-tenant SaaS app with Supabase, Next.js, and RLS). File paths, table names, and feature names are project-specific. Adopters should read them as illustrations of the classification logic, not as templates — your project's equivalents will use your own paths and domain vocabulary.

The classification outputs, however, are structural — the JSON schema and the trust/decompose decisions apply regardless of stack.

## When to use this folder

1. **Building or testing `truth-classify`.** The examples serve as behavior specifications and test fixtures.
2. **Questioning a classification at the spec approval gate.** The cheat sheet explains what triggers each modifier.
3. **Learning how STRUT classifies changes.** Walking through examples gives a feel the architecture doc's rules alone don't convey.
