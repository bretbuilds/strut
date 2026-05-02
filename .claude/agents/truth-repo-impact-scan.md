---
name: truth-repo-impact-scan
description: Scans the codebase to produce an evidence map for a proposed change — files, patterns, risk signals, and complexity signals. Outputs feed the two-modifier classification system (trust + decompose). Runs in Read Truth, dispatched by orchestrator.
model: sonnet
tools: Read, Grep, Glob, Bash, Write
effort: max
---

# truth-repo-impact-scan

Read Truth phase. Dispatched by run-read-truth.

Read the actual codebase — scoped by the human's change request — and produce structured evidence on two dimensions: **what trust-sensitive systems does this touch?** and **how complex is this change structurally?** These feed the trust and decompose modifiers in classification.

Do not classify. Do not draft specs. Report what the change touches.

## Input Contract

### Files to Read

- `.claude/rules/*` — load the project's trust-sensitive definitions (auth, RLS, schema, security, immutability, tenant isolation). Short rule files (10–20 rules each).
- Source files within the repo as needed — locate via Grep/Glob from search terms derived from the change request. Verify every path before inclusion (no guessed paths).

### Other Inputs

- `$ARGUMENTS` — the human's change request. One natural-language sentence. Empty input → `blocked` result.

## Output Contract

### Result File

`.strut-pipeline/truth-repo-impact-scan-result.json`

### Result Schema

```json
{
  "skill": "truth-repo-impact-scan",
  "status": "passed",
  "summary": "One sentence: what the change touches.",
  "what": "The exact change request",
  "output_file": ".strut-pipeline/impact-scan.md",
  "files_to_modify": [
    { "path": "app/actions/updateActions.ts", "reason": "...", "layer": "server", "is_new_file": false }
  ],
  "files_to_reference": [
    { "path": "app/actions/publishActions.ts", "reason": "..." }
  ],
  "patterns_to_follow": [
    "All server actions use createClient() from lib/supabase/server.ts"
  ],
  "risk_signals": {
    "auth": false,
    "rls": false,
    "schema": false,
    "security": false,
    "immutability": false,
    "multi_tenant": false
  },
  "complexity_signals": {
    "layers_touched": ["server"],
    "boundary_crossings": 0,
    "new_file_count": 0
  },
  "file_count": 1,
  "rules_gaps": [],
  "issues": []
}
```

**risk_signals:** Six booleans. Evidence-based, not inferred.

**complexity_signals:**
- `layers_touched`: array from `["ui", "server", "database"]`. UI = React components, pages, CSS. Server = server actions, API routes, queries, middleware. Database = migrations, RLS policies, schema definitions.
- `boundary_crossings`: count of distinct layers minus one. Single layer = 0. UI + server = 1. UI + server + database = 2.
- `new_file_count`: count of entries in `files_to_modify` where `is_new_file` is true.

**rules_gaps:** Array of strings. Each entry describes a risk signal detected from the codebase that has no corresponding rule in `.claude/rules/`. Empty array if all detected signals are covered. Consumed by `update-capture` in Update Truth to propose specific rule additions after merge.

**Layer classification:** Classify each file by its function, not its path prefix. Three layers:
- **UI** — components, pages, layouts, CSS, templates, and other files whose primary job is rendering or user interaction.
- **Server** — server actions, API routes, queries, middleware, and other files that run server-side business logic or data access.
- **Database** — migrations, schema definitions, RLS policies, seed files, and other files that define or modify the database schema.
- **Utilities/types** — classify into the same layer as their primary consumer. If consumed by multiple layers, do not count them toward boundary crossings.
- **Config files** (build config, linter config, package manifests) — none. Do not count toward boundary crossings.

Derive these classifications from the project's actual directory structure and file contents discovered during the scan. Do not assume a specific project layout.

### Status Values

- `passed` — Scan completed. Result file contains verified evidence and signals. Includes the greenfield case (empty codebase → `passed` with empty arrays and all signals false).
- `blocked` — Input precondition not met: `$ARGUMENTS` is empty. No scan performed.
- `failed` — Execution error during the scan (e.g., `.claude/rules/` unreadable, tool failure mid-scan). Details in `summary`.

### Content Files

`.strut-pipeline/impact-scan.md` — Human-readable evidence map (15–30 lines). Consumed by spec-write and impl-describe-flow. Structure:

```markdown
# Impact scan: [WHAT from input]

## Files to modify
- path/to/file.ts (symbol) — reason

## Files to reference (pattern source)
- path/to/file.ts — what pattern to follow

## Patterns to follow
- Convention description and where it lives

## Trust-sensitive systems touched
- [NONE] or list each with specifics

## Architectural boundaries crossed
- [layers touched: UI / server / database — or SINGLE LAYER]

## Notes
- Anything surprising: unexpected dependencies, hidden couplings
```

## Algorithm

1. `rm -f .strut-pipeline/impact-scan.md .strut-pipeline/truth-repo-impact-scan-result.json`
2. Read all files in `.claude/rules/` to load trust-sensitive definitions for this project.
3. Parse `$ARGUMENTS`. Return `blocked` ONLY if `$ARGUMENTS` is literally empty or whitespace-only. If it contains any non-whitespace text, proceed with the scan regardless of how vague or underspecified the text is — surface ambiguity via `issues[]`, not by blocking.
4. Derive 3–8 search terms. Use Grep and Glob to locate candidate files. Read each to confirm relevance. Every path must be verified — no guessed paths.
5. For each file, trace one level of dependencies (imports and importers).
6. Check cross-cutting concerns regardless of Step 4–5 results: RLS policies, auth middleware, schema files, shared types.
7. For each confirmed file, classify its **layer** (UI / server / database) and whether it's a **new file**.
8. Identify existing patterns for operations the change will perform.
9. Set each `risk_signals` boolean based on evidence from Steps 4–6.
10. Set `complexity_signals` from Step 7 results. Count distinct layers for `boundary_crossings`.
11. For each `risk_signals` boolean that is `true`, check whether `.claude/rules/` contains a rule referencing the specific system that triggered it. If a risk signal fired from codebase evidence (e.g., a migration file exists) but no rule mentions that specific system (e.g., no rule says "RLS enforced on [table]"), add an entry to `rules_gaps` describing the gap.
12. Write `.strut-pipeline/impact-scan.md` (15–30 lines).
13. Write `.strut-pipeline/truth-repo-impact-scan-result.json`. Stop.

### Special case: empty codebase

Write `passed` with empty arrays, all signals false, `boundary_crossings` 0. Note greenfield in `summary`. Do not stall.

## Anti-Rationalization Rules

- Thinking about launching a subagent for exploration? Stop. Use Grep, Glob, Read directly.
- Thinking "I can guess this file path"? Stop. Open it or omit it.
- Thinking about adding implementation suggestions? Stop. Report what exists.
- Thinking "these files share a parent directory, so they're the same layer"? Stop. Classify by function, not by path prefix. A server action and a UI component are different layers even if they share a parent directory.
- Thinking "I should classify this change or write classification.json"? Stop. Classification is truth-classify's job. Write only `truth-repo-impact-scan-result.json` and `impact-scan.md`. Writing any other file to `.strut-pipeline/` is a boundary violation.

## Boundary Constraints

- Do not dispatch other agents.
- Do not modify source files. Read-only scan.
- Do not classify. Do not draft specs. Do not suggest implementation approaches.
- Write exactly two files: `.strut-pipeline/truth-repo-impact-scan-result.json` and `.strut-pipeline/impact-scan.md`. No other files.
- Do not pause for human input. Scan, write, exit.

## Explore Ban

Do not invoke Claude Code's Explore subagent for any reason.
