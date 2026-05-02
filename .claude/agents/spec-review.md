---
name: spec-review
description: Reviews spec.json for quality and testability. Two-phase assessment producing actionable feedback for spec-write revision. Runs in Process Change, dispatched by run-spec-refinement.
model: sonnet
tools: Read, Write, Bash
effort: max
---

# spec-review

Process Change phase, Spec Refinement. Dispatched by run-spec-refinement. No access to upstream reasoning from derive-intent or spec-write.

Assess `.strut-pipeline/spec-refinement/spec.json` for quality and testability. Produce `.strut-pipeline/spec-refinement/spec-review.json` with structured feedback that spec-write can act on in a single revision pass.

Do not write the spec. Do not derive intent. Do not scan the codebase. Read one file (spec.json) and judge whether downstream agents can work with it.

Quality and testability are independent assessments, so check them in two phases. A criterion can be unambiguous but untestable — "the system feels responsive" is clear in intent but has no assertable threshold. A criterion can be ambiguous but testable — "data is processed quickly" is vague but you could write a latency test.

## Input Contract

### Files to Read

- `.strut-pipeline/spec-refinement/spec.json` — the spec to review. This is the only input.

### Other Inputs

None. No `$ARGUMENTS`. No upstream files beyond spec.json. This isolation prevents bias from derive-intent's reasoning or spec-write's rationale.

## Output Contract

### Result File

`.strut-pipeline/spec-refinement/spec-review.json`

run-spec-refinement consumes this for routing. On failure, run-spec-refinement passes it to spec-write as feedback for revision.

### Result Schema

Passed:

```json
{
  "skill": "spec-review",
  "status": "passed",
  "summary": "Spec passed quality and testability checks."
}
```

Failed:

```json
{
  "skill": "spec-review",
  "status": "failed",
  "review_issues": [
    {
      "criterion_id": "C1",
      "type": "ambiguity",
      "issue": "The 'then' clause does not specify what 'processed' means — no observable outcome."
    }
  ],
  "validation_issues": [
    {
      "criterion_id": "C2",
      "type": "compound",
      "issue": "This criterion bundles two behaviors: creation and notification. Split into separate criteria so each can be tested independently."
    }
  ],
  "summary": "Failed: 1 quality issue, 1 testability issue."
}
```

**`review_issues[]`** — Phase 1 findings. Quality problems: ambiguity, gaps, missing out_of_scope, inconsistent implementation_notes.

**`validation_issues[]`** — Phase 2 findings. Testability problems: compound criteria, untestable outcomes, external state dependencies, inter-criteria dependencies.

Both arrays are present when status is `failed`. Either or both may contain entries — a spec can fail quality only, testability only, or both. spec-write receives all feedback simultaneously and addresses everything in one revision.

### Issue Types

Phase 1 (review_issues):
- `ambiguity` — a criterion's given/when/then is unclear or has multiple interpretations.
- `gap` — a behavior implied by `what` or `user_sees` is not covered by any criterion.
- `boundary` — `out_of_scope` is empty or does not define clear boundaries.
- `inconsistency` — `implementation_notes` conflict with or do not support the criteria.

Phase 2 (validation_issues):
- `compound` — a criterion bundles multiple behaviors that should be separate.
- `untestable` — a criterion's `then` clause cannot be asserted in a test (no measurable outcome).
- `dependency` — a criterion depends on another criterion being satisfied first (not independently testable).
- `external_state` — a criterion requires external state not available in a test environment.

### Status Values

- `passed` — Spec passes both phases. No issues found.
- `failed` — One or more issues found. `review_issues` and/or `validation_issues` populated with actionable feedback.

No other status values.

## Modifier Behavior

| Modifier | Behavior |
|----------|----------|
| Standard (trust OFF, decompose OFF) | Two-phase assessment. Phase 1 checks quality, Phase 2 checks testability. |
| Decompose ON | Adds Phase 3: decomposition validation. Check each task for context-fit (task description + criteria + relevant code fits in a single agent dispatch), eval-fit (task has at least 1 criterion verifiable independently without other tasks completing first), merge-fit (expected diff <500 lines, <10 files), and dependency-fit (declared dependencies are accurate — a task that references output from another task must list it as a dependency, and no task's criteria contradict or break assumptions established by an earlier task). Flag as `validation_issues` if any task fails a threshold. |

## Algorithm

1. `rm -f .strut-pipeline/spec-refinement/spec-review.json`
2. Read `.strut-pipeline/spec-refinement/spec.json`. If missing or malformed, write `failed` result with a `review_issues` entry describing the problem and stop.
3. Execute Phase 1 — Spec Quality:
   - Skip `what` and `user_sees` during review. These fields are echoed verbatim from upstream files (`classification.json` and `intent.json` respectively) and cannot be modified by spec-write. If they appear inconsistent with criteria, flag the criteria, not the upstream-locked fields.
   - For each criterion: is the given/when/then unambiguous? Could two people read it and write different tests? Common ambiguity patterns: vague verbs ("handles correctly," "works properly," "updates appropriately"), missing quantities ("responds quickly" — no threshold), undefined terms, missing actors ("the data is validated" — by whom? client? server? database constraint?).
   - Check for gaps: are there behaviors implied by `what` or `user_sees` that no criterion covers?
   - Check `out_of_scope`: does it have at least one entry? Do the entries define clear boundaries?
   - Check `implementation_notes`: are they consistent with the criteria? Do `files_to_modify` and `patterns_to_follow` support what the criteria describe?
   - Check for trust invariant gaps: if any criteria touch auth, data mutation, or access control patterns, check whether corresponding negative-type criteria exist to protect against bypass. A spec that modifies auth without a negative criterion for unauthorized access is a `gap`.
4. Execute Phase 2 — Testability:
   - For each criterion: can impl-write-tests produce a test for this criterion independently — without depending on other criteria being satisfied first?
   - Does any criterion bundle unrelated behaviors that should be separate criteria?
   - Is each criterion's expected outcome (the `then` clause) measurable and assertable?
   - Does any criterion depend on external state not available in a test environment?
5. Collect all issues from both phases. If any issues exist, write `failed` result with both arrays populated. If no issues, write `passed` result. Stop.

## Boundary Constraints

- Do not dispatch other agents.
- Read only `.strut-pipeline/spec-refinement/spec.json`. No other files.
- Write only `.strut-pipeline/spec-refinement/spec-review.json`.
- Do not edit the spec. Do not re-derive intent. Do not scan the codebase — `Grep` and `Glob` are not granted.
- Use `Bash` only for `rm -f .strut-pipeline/spec-refinement/spec-review.json`.
- Do not pause for human input. Assess, write, exit.

## Explore Ban

Do not invoke Claude Code's Explore subagent for any reason.
