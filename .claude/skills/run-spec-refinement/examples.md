# run-spec-refinement Examples

## Write-review loop: iteration 1 fails, iteration 2 passes

### Iteration 1

spec-write produces `spec.json` with `status: "drafted"`. spec-review reads it and writes `spec-review.json`:

```json
{
  "skill": "spec-review",
  "status": "failed",
  "review_issues": [
    {
      "criterion_id": "C2",
      "type": "ambiguity",
      "issue": "The 'then' clause says 'response is saved' — does not specify where (database row? in-memory state?) or what observable confirms it."
    }
  ],
  "validation_issues": [
    {
      "criterion_id": "C3",
      "type": "compound",
      "issue": "This criterion bundles two behaviors: creating the response record and sending a notification. Split into separate criteria so each can be tested independently."
    }
  ],
  "summary": "Failed: 1 quality issue, 1 testability issue."
}
```

Orchestrator reads `status: "failed"` → increments iteration to 2 → re-dispatches spec-write.

### Iteration 2

spec-write reads the existing `spec.json` AND `spec-review.json` as feedback. Per its feedback handling rules, it preserves everything the feedback did not flag (C1 unchanged), fixes C2's ambiguity, and splits C3 into C3 + C4.

spec-review reads the revised spec and writes:

```json
{
  "skill": "spec-review",
  "status": "passed",
  "summary": "Spec passed quality and testability checks."
}
```

Orchestrator reads `status: "passed"` → says `Spec refinement complete. Spec approved after 2 iteration(s).` → returns to run-process-change.

## Key behavior: what spec-write sees on re-dispatch

On iteration 2+, spec-write's input contract has two feedback-relevant files:

| File | What spec-write does with it |
|------|------------------------------|
| `.pipeline/spec-refinement/spec.json` | Reads the existing spec. Preserves everything not flagged by feedback. |
| `.pipeline/spec-refinement/spec-review.json` | Reads `review_issues[]` and `validation_issues[]`. Addresses every issue in one revision pass. |

spec-write does NOT re-read `intent.json` or the scan results on revision — those were consumed on the first draft. The revision is scoped to the review feedback.

## Budget exhaustion

If spec-review returns `status: "failed"` on iteration 5, the orchestrator says:

```
Spec cycle exhausted (5 iterations). Last review feedback in .pipeline/spec-refinement/spec-review.json. Escalating to human.
```

And stops. run-process-change receives the failure and writes `process-change-state.json` with `status: "failed"`, `failed_at: "spec_refinement"`.
