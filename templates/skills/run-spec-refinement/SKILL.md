---
name: run-spec-refinement
description: Sub-orchestrator for the spec cycle. Dispatches derive-intent, write-spec, and review-spec in sequence. Manages the write→review feedback loop with a max 5 iteration budget. Runs in Process Change, dispatched by run-process-change.
---

# run-spec-refinement

Process Change phase, Spec Refinement. Dispatched by run-process-change.

Derive structured intent, produce a spec, review it for quality and testability, and loop write→review until the spec passes or the iteration budget is exhausted. Return to run-process-change with a passed spec or a failure for human escalation. Do not derive intent, write specs, or review specs directly.

## Dispatches

- spec-derive-intent (agent) — once, at the start
- spec-write (agent) — once initially, then on each review failure (up to 5 total)
- spec-review (agent) — once per spec-write dispatch

## Input Contract

### Files Read (for status routing only)

- `.strut-pipeline/spec-refinement/intent.json` — status check after derive-intent
- `.strut-pipeline/spec-refinement/spec.json` — status check after spec-write
- `.strut-pipeline/spec-refinement/spec-review.json` — status check after spec-review; on failure, this file becomes spec-write's feedback source on the next iteration

### Other Inputs

- The human's change request, available in conversation context from run-process-change (which received it from run-strut).

### Prerequisite Files

These must exist before this skill runs (produced by Read Truth):

- `.strut-pipeline/classification.json`
- `.strut-pipeline/impact-scan.md`
- `.strut-pipeline/truth-repo-impact-scan-result.json`

If any prerequisite is missing, say: `Missing Read Truth output. Run Read Truth first.` Stop.

## Output Contract

### Result Files

None. Outputs are the files the dispatched agents write:

- `.strut-pipeline/spec-refinement/intent.json` (written by spec-derive-intent)
- `.strut-pipeline/spec-refinement/spec.json` (written by spec-write)
- `.strut-pipeline/spec-refinement/spec-review.json` (written by spec-review)

### Return to run-process-change

On success: return with `.strut-pipeline/spec-refinement/spec-review.json` containing `status: "passed"` and `.strut-pipeline/spec-refinement/spec.json` as the approved spec.

On failure: report the failure reason and stop. run-process-change escalates to human.

## Dispatch Sequence

### Step 1: Verify prerequisites

```bash
mkdir -p .strut-pipeline/spec-refinement
```

Check that `.strut-pipeline/classification.json`, `.strut-pipeline/impact-scan.md`, and `.strut-pipeline/truth-repo-impact-scan-result.json` all exist. If any is missing, say: `Missing Read Truth output: [name]. Run Read Truth first.` Stop.

Initialize the iteration counter: `iteration = 0`.

### Step 2: Dispatch derive-intent

Dispatch the spec-derive-intent agent via the Agent tool with `subagent_type: "spec-derive-intent"`. Pass the human's change request as the prompt.

When the agent completes, check: does `.strut-pipeline/spec-refinement/intent.json` exist?

- **Yes:** Read ONLY the `status` field. If `"passed"`, continue to Step 3. If `"failed"`, say `Intent derivation failed. Check .strut-pipeline/spec-refinement/intent.json.` Stop.
- **No:** Say `Derive-intent did not produce output.` Stop.

**Step pause.** If `.strut-pipeline/step-mode` exists, say `STEP: spec-derive-intent — passed. Output: .strut-pipeline/spec-refinement/intent.json. Next: spec-write.` Ask `Continue? (yes / abort)` and wait. If `abort`, say `Pipeline stopped at step pause.` and stop.

### Step 3: Dispatch spec-write

Increment: `iteration = iteration + 1`.

Dispatch the spec-write agent via the Agent tool with `subagent_type: "spec-write"`. Pass the change request as the prompt.

When the agent completes, check: does `.strut-pipeline/spec-refinement/spec.json` exist?

- **Yes:** Read ONLY the `status` field. If `"drafted"`, continue to Step 4. If `"failed"`, say `Spec-write failed. Check .strut-pipeline/spec-refinement/spec.json.` Stop.
- **No:** Say `Spec-write did not produce output.` Stop.

**Step pause.** If `.strut-pipeline/step-mode` exists, say `STEP: spec-write — drafted (iteration [iteration]). Output: .strut-pipeline/spec-refinement/spec.json. Next: spec-review.` Ask `Continue? (yes / abort)` and wait. If `abort`, say `Pipeline stopped at step pause.` and stop.

### Step 4: Dispatch spec-review

Dispatch the spec-review agent via the Agent tool with `subagent_type: "spec-review"`. Pass a prompt instructing it to read and review `.strut-pipeline/spec-refinement/spec.json`.

When the agent completes, check: does `.strut-pipeline/spec-refinement/spec-review.json` exist?

- **Yes:** Read ONLY the `status` field.
  - If `"passed"`:
    **Step pause.** If `.strut-pipeline/step-mode` exists, say `STEP: spec-review — passed (iteration [iteration]). Output: .strut-pipeline/spec-refinement/spec-review.json. Next: spec approval gate.` Ask `Continue? (yes / abort)` and wait. If `abort`, say `Pipeline stopped at step pause.` and stop.
    Say `Spec refinement complete. Spec approved after [iteration] iteration(s).` Return to run-process-change.
  - If `"failed"`: continue to Step 5.
- **No:** Say `Spec-review did not produce output.` Stop.

### Step 5: Check iteration budget

If `iteration >= 5`: say `Spec cycle exhausted (5 iterations). Last review feedback in .strut-pipeline/spec-refinement/spec-review.json. Escalating to human.` Stop.

Otherwise: say `Spec review failed (iteration [iteration] of 5). Re-dispatching spec-write with feedback.`

**Step pause.** If `.strut-pipeline/step-mode` exists, say `STEP: spec-review — failed (iteration [iteration] of 5). Output: .strut-pipeline/spec-refinement/spec-review.json. Next: spec-write (retry).` Ask `Continue? (yes / abort)` and wait. If `abort`, say `Pipeline stopped at step pause.` and stop.

Go to Step 3 (dispatch spec-write again). spec-write will read `spec-review.json` as its feedback source per its own input contract.

## Examples

Read `examples.md` in this skill's directory for a worked write-review loop (iteration 1 fails, iteration 2 passes with feedback) and what spec-write sees on re-dispatch.

## Anti-Rationalization Rules

- Thinking "spec-review found minor issues, I should pass it anyway"? Stop. You check status, not severity. `"failed"` means re-dispatch spec-write. Only `"passed"` exits the cycle.
- Thinking "I should read the spec content to understand what went wrong"? Stop. You route on status. spec-write reads the review feedback, not you.
- Thinking "derive-intent failed, I should try running spec-write anyway"? Stop. spec-write requires intent.json. No intent, no spec.
- Thinking "5 iterations seems excessive, I should stop at 3"? Stop. The budget is 5. Convergence is spec-write and spec-review's concern, not yours.

## Boundary Constraints

- Dispatch only: spec-derive-intent, spec-write, spec-review.
- Do not derive intent, write specs, or review specs itself.
- Do not read content fields from agent result files — only `status`.
- Do not modify agent output files.
- Do not scan the codebase. No `Grep`/`Glob`.
- Do not handle spec approval. run-process-change handles the human gate after this skill returns.
- Do not handle PR rejection feedback. run-process-change writes `pr-rejection-feedback.json` before re-dispatching this skill; spec-write reads it per its own feedback precedence rules.
- Do not launch the Explore agent.
- Do not proceed to implementation. run-process-change handles phase sequencing.
