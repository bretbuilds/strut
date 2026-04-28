# Decision Log

Append-only record of non-obvious project decisions: technology choices, architectural patterns, approach calls, tradeoffs made under time pressure. This file captures *why your project is built the way it is* — distinct from `docs/strut-architecture/architectural-decisions.md`, which captures why STRUT is built the way it is.

## Rules

1. Append only. Never edit or delete existing entries. If a decision is superseded, add a new entry that references the old one.
2. Capture non-obvious decisions only. Default choices (using the recommended library, following the existing pattern) don't need entries.
3. Entries come from two sources: manual (you write them when you make a decision worth capturing) and proposed (`update-capture` suggests entries after significant changes; you review and append).

## Entry format

```
## [YYYY-MM-DD] [Short title]

**Decision:** What was decided.

**Context:** What made this decision necessary. What alternatives were considered.

**Consequences:** What this commits the project to, what it rules out.

**Source:** Change that prompted this (spec title, PR number, or "manual").
```

## What belongs here

- Technology selection with non-obvious tradeoffs ("chose Postgres over MongoDB because...")
- Architectural patterns adopted for the project ("all server actions return typed results via...")
- Scope boundaries made explicit ("we decided V1 does not support X because...")
- Deferred work with trigger conditions ("multi-region support deferred until N customers request...")
- Constraints the codebase won't make obvious on its own

## What doesn't belong here

- Decisions that are self-evident from reading the code
- STRUT architecture decisions (those are in `docs/strut-architecture/architectural-decisions.md`)
- Implementation details that belong in code comments
- Transient choices that don't shape future work

## If this file is empty

That's expected at the start of a project. Entries accrue as you make decisions worth capturing. If weeks pass without any entries, either no non-obvious decisions have been made (fine) or they're being made but not captured (worth revisiting).

---

<!-- Entries begin below this line. Most recent at the bottom. -->