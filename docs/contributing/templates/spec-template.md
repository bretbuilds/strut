# Spec Template

<!-- This is the human-review rendering of a spec. The authoritative format is JSON,
     written by spec-write to .pipeline/spec-refinement/spec.json per the schema in
     docs/strut-architecture/pre-build-decisions.md. The fields below map directly to JSON fields;
     annotations show which section corresponds to which field. -->

---

## Header

**What:** [one-sentence change description, echoed from classification.json]
**Why:** [why this change matters — sourced from intent.json's business_context]
**User sees:** [what the user observes after the change, from intent.json]
**Modifiers:** trust [OFF | ON] · decompose [OFF | ON]

<!-- Maps to JSON fields: `what`, `user_sees`. `why` is upstream context from intent.json
     (field: business_context) — included here for human reviewers, not written into spec.json.
     Under trust OFF, `why` may be brief or omitted. -->

### Must Never

<!-- Human-readability summary of the negative criteria below. Under trust OFF, this
     section may be empty or contain only baseline invariants. Under trust ON, list
     every must_never from intent.json — each corresponds to a negative criterion
     (MN1, MN2, ...) in the Criteria section. -->

- [invariant description, e.g., "Cross-tenant data access on action_responses"]

---

## Criteria

Given/When/Then acceptance criteria. Each is independently testable. Each has an `id`, a `type` (positive or negative), and — if negative — a `source` tracing back to the intent's must_never entry.

### C1 · positive

- **Given** [context]
- **When** [action]
- **Then** [expected outcome]

### C2 · positive

- **Given** [context]
- **When** [action]
- **Then** [expected outcome]

<!-- Under trust ON, negative criteria (MN1, MN2, ...) appear here alongside positive ones.
     They are not a separate section — impl-write-tests treats all criteria uniformly. -->

### MN1 · negative

- **Given** [context where the trust boundary could be violated]
- **When** [the action that might violate it]
- **Then** [the violation is rejected]
- **Source:** must_never: [invariant description from intent.json]

<!-- Maps to JSON field: `criteria[]` — array of {id, given, when, then, type, source?}.
     Target 3-7 criteria total. Each must_never from intent becomes one negative criterion. -->

---

## Tasks

Always present. Decompose OFF = one task with all criteria_ids. Decompose ON = up to 5 tasks, each with a subset.

### task-1 — [one-sentence task description]

- **Criteria:** C1, C2, MN1
- **Files:** [from implementation_notes.files_to_modify]
- **Depends on:** [previous task id, or "none"]

<!-- Maps to JSON field: `tasks[]` — array of {id, description, criteria_ids}.
     Decompose ON adds the constraint that each task must be independently testable. -->

---

## Implementation Notes

Grounding for impl-write-code. Copied from impact-scan.md — not re-derived.

**Files to modify:**
- `[path]` — [reason this file is touched]

**Patterns to follow:**
- [convention extracted from existing code]

**Files to reference:**
- `[path]` — [why this file is relevant but not modified]

<!-- Maps to JSON field: `implementation_notes` with subfields `files_to_modify[]`,
     `patterns_to_follow[]`, `files_to_reference[]`. Grounding comes from the scan,
     not from spec-write's own reasoning. -->

<!-- For empty or early codebases: state "No existing patterns yet — this feature
     establishes the pattern for [X]." Do not leave blank. -->

---

## Out of Scope

What this spec explicitly does not cover. At least one entry required — forces spec-write to think about boundaries.

- [adjacent feature deferred to a later change]
- [edge case explicitly excluded, with reason]

<!-- Maps to JSON field: `out_of_scope[]` — array of strings. spec-review verifies at
     least one entry exists. -->