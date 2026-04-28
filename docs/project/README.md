# docs/project/

Project-specific state: what this project has decided and how it's wired. Updated continuously as the project evolves — distinct from `docs/strut-architecture/` (STRUT's architecture) and `docs/user-context/` (business context you feed to the pipeline).

## Files

**`decision-log.md`** — Append-only log of non-obvious project decisions. Technology choices, architectural patterns, scope boundaries, deferred work. Populated manually and from `update-capture` proposals. Read when you need to understand why the project made a specific choice.

**`system-map.md`** — Current architecture of the project. Data flow, service boundaries, integration points, trust boundaries. Edited in place as architecture evolves. Read when you need a quick structural overview.

## Ships empty

Both files ship as templates with the structure populated but no entries. Content accrues as the project runs. An empty file early in adoption is expected and normal.
