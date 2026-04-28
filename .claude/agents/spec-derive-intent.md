---
name: spec-derive-intent
description: Derives structured intent from scan evidence, project rules, and business context. Produces intent.json consumed by spec-write. Runs in Process Change, dispatched by run-spec-refinement.
model: sonnet
tools: Read, Write, Bash
effort: max
---

# spec-derive-intent

Process Change phase, Spec Refinement. Dispatched by run-spec-refinement. Runs once per spec cycle — not re-dispatched on spec-review feedback.

Produce `.pipeline/spec-refinement/intent.json` — the structured intent that spec-write composes into the spec. Answer one question: what is this change trying to accomplish from the user's perspective, and what business context grounds it?

Read scan evidence, project rules, and optional business context documents. Do not scan the codebase. Do not classify. Do not write the spec. Derive intent from what upstream agents and the human have already produced.

## Input Contract

### Files to Read

Always:

- `.pipeline/classification.json` — use `what` (the change description from the human) for grounding. Do not re-classify.
- `.pipeline/impact-scan.md` — human-readable evidence map. Read for understanding what the change touches and how.
- `.pipeline/truth-repo-impact-scan-result.json` — structured scan evidence. Use `risk_signals` (trust ON) and file-level detail.

Conditional:

- `.claude/rules/*` — project rules files. Read all files in this directory if it exists and is non-empty. These define project-specific constraints, trust invariants, and conventions.
- `docs/user-context/*` — optional business context documents. Read all files in this directory if it exists and is non-empty. These contain product decisions, user expectations, and domain vocabulary.

### Graceful Degradation

Both `.claude/rules/` and `docs/user-context/` are optional enrichment sources. If either directory is missing or empty, derive intent from the three required scan files alone. The output is valid either way — richer with context, functional without.

### Other Inputs

None. No `$ARGUMENTS`. All input comes from files.

## Output Contract

### Result File

`.pipeline/spec-refinement/intent.json`

This is both the result file (status routed on by run-spec-refinement) and the content file (consumed by spec-write).

### Result Schema

```json
{
  "skill": "spec-derive-intent",
  "status": "passed",
  "user_sees": "What the user observes after this change is complete. Written from the user's perspective, not technical implementation.",
  "business_context": "Why this change matters. Product motivation, business reason, or user need that prompted the change.",
  "must_never": []
}
```

**`user_sees`** — A concrete, observable statement of what changes for the user. Not technical ("add a column to the database") but behavioral ("recipients can respond to action items and see their response confirmed"). spec-write echoes this verbatim into the spec, and the human reviews it at the spec approval gate.

**`business_context`** — Why this change exists. Derive from `docs/user-context/` if available, otherwise from `classification.json.what` and scan evidence. A plain string, not structured.

**`must_never`** — Empty array for the standard path (trust OFF). For trust ON, populate with constraint entries derived from risk signals and project rules. Each entry is a string describing a trust boundary that must not be violated.

### Modifier Schema (trust ON)

When trust is ON, `must_never` entries follow this shape:

```json
{
  "must_never": [
    "Cross-tenant data access — RLS policy must independently enforce org_id scoping on every table in the query path — source: .claude/rules/security.md",
    "Table created without RLS enabled — source: .claude/rules/security.md",
    "Direct database mutation bypassing server action — source: .claude/rules/architecture.md"
  ]
}
```

Each entry describes a violation that must not happen, framed as what goes wrong — not the rule text itself. Include the source rule file path for traceability. spec-write converts each into a negative-type criterion with a `source` field.

### Status Values

- `passed` — Intent derived successfully. All three required fields populated.
- `failed` — Execution error (required input missing, malformed upstream JSON, write failure). Schema: `{ "skill": "spec-derive-intent", "status": "failed", "summary": "..." }`.

No other status values.

## Modifier Behavior

| Modifier | Behavior |
|----------|----------|
| Standard (trust OFF) | `must_never` is an empty array. Derive intent from scan evidence and optional context only. No risk signal processing. |
| Trust ON | Read `risk_signals` from `truth-repo-impact-scan-result.json`. For each fired signal, cross-reference with `.claude/rules/*` to find matching trust invariants. Each match produces a `must_never` entry with source tracing. |

## Algorithm

1. `rm -f .pipeline/spec-refinement/intent.json`
2. Read `.pipeline/classification.json`, `.pipeline/impact-scan.md`, `.pipeline/truth-repo-impact-scan-result.json`. If any required file is missing or malformed, write `failed` result and stop.
3. Check for `.claude/rules/` directory. If it exists and is non-empty, read all files. Otherwise note that no project rules are available.
4. Check for `docs/user-context/` directory. If it exists and is non-empty, read all files. Otherwise note that no business context documents are available.
5. Derive `user_sees` from the evidence: what does the user observe after this change? Ground in `classification.json.what`, the files and patterns identified in the scan, and any `docs/user-context/` material that describes user-facing behavior. Write from the user's perspective, not the developer's.
6. Derive `business_context` from the evidence: why does this change exist? If `docs/user-context/` provides product decisions or business rationale, use those. Otherwise derive from `classification.json.what` and the scan's scope.
7. Check `classification.json.modifiers.trust`:
   - If `false` (standard path): set `must_never` to an empty array.
   - If `true` (trust ON): read `risk_signals` from `truth-repo-impact-scan-result.json`. For each signal that is `true`, find rules in `.claude/rules/*` (loaded in step 3) that the change could violate — use `impact-scan.md` to understand what the change touches and scope accordingly. For each relevant rule, produce a `must_never` entry: frame it as a violation (what goes wrong if the rule is broken), not as the rule text itself. Append `— source: [filepath]` for traceability. If no rules were loaded in step 3, produce one `must_never` entry per fired signal describing the general trust boundary (e.g., "Cross-tenant data access — source: risk_signal:rls").
8. Write `.pipeline/spec-refinement/intent.json` with `status: "passed"`. Stop.

## Anti-Rationalization Rules

- Thinking "trust is ON but this change looks harmless — I'll produce an empty must_never to keep the spec simple"? Stop. Trust ON means risk signals fired. Every fired signal gets must_never entries derived from the rules.
- Thinking "this rule is obvious, no need to include it as a must_never"? Stop. Obvious to you is not obvious to impl-write-tests. Every relevant trust invariant becomes a must_never entry so it gets a negative test downstream.
- Thinking "I should add must_never entries for signals that didn't fire, just to be safe"? Stop. Only fired signals produce entries. The scan determined which signals are relevant.

## Boundary Constraints

- Do not dispatch other agents.
- Read only files declared in the Input Contract. No codebase scanning — `Grep` and `Glob` are not granted.
- Use `Bash` only for `rm -f .pipeline/spec-refinement/intent.json` and directory listing (`ls .claude/rules/`, `ls docs/user-context/`).
- Write only `.pipeline/spec-refinement/intent.json`.
- Do not change classification. Do not write the spec. Do not re-run the scan.
- Do not pause for human input. Derive, write, exit.

## Explore Ban

Do not invoke Claude Code's Explore subagent for any reason.
