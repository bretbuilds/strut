---
name: run-spec-refinement
description: Sub-orchestrator for the spec cycle. Dispatches derive-intent, write-spec, and review-spec in sequence. Manages the write→review feedback loop with a 5-iteration budget per round; archives iterations to support spec-write learning across attempts and gates to a spec_stuck escalation when the budget is exhausted. Runs in Process Change, dispatched by run-process-change.
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
- `.strut-pipeline/spec-refinement/spec-review.json` — status check after spec-review

### Files Read (filesystem state, not routing)

- `.strut-pipeline/spec-refinement/iterations/iter-*-spec.json` — counted (only) to derive the current iteration number for naming the next archive

This skill does not read content fields from any spec-refinement file. spec-write and spec-review read iteration content for their own purposes; this orchestrator routes on existence and counts only.

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

- `.strut-pipeline/spec-refinement/spec-refinement-result.json` — written by this skill ONLY when the iteration budget is exhausted. Schema: `{ "skill": "run-spec-refinement", "status": "exhausted", "iterations": <count>, "iterations_dir": ".strut-pipeline/spec-refinement/iterations/" }`. On a successful pass, this file is not written; run-process-change checks for its presence to detect exhaustion.

The dispatched agents also write:

- `.strut-pipeline/spec-refinement/intent.json` (spec-derive-intent)
- `.strut-pipeline/spec-refinement/spec.json` (spec-write — current draft)
- `.strut-pipeline/spec-refinement/spec-review.json` (spec-review — current review)
- `.strut-pipeline/spec-refinement/iterations/iter-N-spec.json` and `iter-N-review.json` — archived copies of failed iterations, written by this skill before re-dispatching spec-write. Final passing iteration is NOT archived (its content is the same as `spec.json`).

### Return to run-process-change

On success: return with `spec-review.json` containing `status: "passed"` and `spec.json` as the approved spec.

On exhaustion: write `spec-refinement-result.json` with `status: "exhausted"` and stop. run-process-change reads this file and routes to the spec_stuck gate.

On other failures (intent/spec/review missing or malformed): report the failure reason and stop. run-process-change escalates to human.

## Dispatch Sequence

### Step 1: Verify prerequisites

```bash
mkdir -p .strut-pipeline/spec-refinement
mkdir -p .strut-pipeline/spec-refinement/iterations
rm -f .strut-pipeline/spec-refinement/spec-refinement-result.json
```

Check that `.strut-pipeline/classification.json`, `.strut-pipeline/impact-scan.md`, and `.strut-pipeline/truth-repo-impact-scan-result.json` all exist. If any is missing, say: `Missing Read Truth output: [name]. Run Read Truth first.` Stop.

This skill does NOT manage round transitions. Whatever state is on disk in `.strut-pipeline/spec-refinement/` is what spec-write and spec-review consume. run-process-change owns the new-run cleanup and the spec_stuck-guidance round transition (move `iterations/` → `iterations-archive/round-N/`, write `human-guidance.md`); see that skill's Step 0 (new run) and Step 6c (spec_stuck resume) for the mechanics.

The iteration counter is always derived from the filesystem: `iteration = count of iterations/iter-*-spec.json files + 1` (the +1 accounts for the about-to-be-dispatched iteration). Never track iteration in conversation memory.

The budget is hardcoded at **5** per round.

### Step 2: Dispatch derive-intent

Dispatch the spec-derive-intent agent via the Agent tool with `subagent_type: "spec-derive-intent"`. Pass the human's change request as the prompt.

When the agent completes, check: does `.strut-pipeline/spec-refinement/intent.json` exist?

- **Yes:** Read ONLY the `status` field. If `"passed"`, continue to Step 3. If `"failed"`, say `Intent derivation failed. Check .strut-pipeline/spec-refinement/intent.json.` Stop.
- **No:** Say `Derive-intent did not produce output.` Stop.

**Step pause.** If `.strut-pipeline/step-mode` exists, say `STEP: spec-derive-intent — passed. Output: .strut-pipeline/spec-refinement/intent.json. Next: spec-write.` Ask `Continue? (yes / abort)` and wait. If `abort`, say `Pipeline stopped at step pause.` and stop.

### Step 3: Dispatch spec-write

Compute the current iteration: `iteration = (count of iterations/iter-*-spec.json files) + 1` (the +1 accounts for the dispatch we're about to make).

Dispatch the spec-write agent via the Agent tool with `subagent_type: "spec-write"`. Pass the change request as the prompt. spec-write reads its full input precedence on its own — `human-guidance.md` (top), `iterations/iter-*-review.json` (current round failures), `iterations-archive/round-*/iter-*-review.json` (archived prior rounds), then `intent.json` and the change request.

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

### Step 5: Archive iteration and check budget

The just-completed iteration failed review. Before deciding whether to retry or escalate, archive the iteration's spec and review (substitute the current `<iteration>` value computed in Step 3):

```bash
cp .strut-pipeline/spec-refinement/spec.json        .strut-pipeline/spec-refinement/iterations/iter-<iteration>-spec.json
cp .strut-pipeline/spec-refinement/spec-review.json .strut-pipeline/spec-refinement/iterations/iter-<iteration>-review.json
```

After archiving, the iteration count on disk equals the number of iterations completed in this round (always equal to `<iteration>` since we just archived it). If `<iteration>` `>= 5`, the budget is exhausted. Write `spec-refinement-result.json` (substitute the iteration value):

```json
{
  "skill": "run-spec-refinement",
  "status": "exhausted",
  "iterations": <iteration>,
  "iterations_dir": ".strut-pipeline/spec-refinement/iterations/"
}
```

Say: `Spec cycle exhausted (5 iterations) for this round. Iteration history in .strut-pipeline/spec-refinement/iterations/. Escalating to spec_stuck gate.` Stop. run-process-change reads `spec-refinement-result.json` and routes to the spec_stuck gate.

Otherwise (budget remains): say `Spec review failed (iteration [iteration] of 5). Re-dispatching spec-write with feedback.`

**Step pause.** If `.strut-pipeline/step-mode` exists, say `STEP: spec-review — failed (iteration [iteration] of 5). Output: .strut-pipeline/spec-refinement/spec-review.json. Next: spec-write (retry).` Ask `Continue? (yes / abort)` and wait. If `abort`, say `Pipeline stopped at step pause.` and stop.

Go to Step 3 (dispatch spec-write again). spec-write reads the archived `iter-*-review.json` files plus any `human-guidance.md` per its own input contract.

## Examples

Read `examples.md` in this skill's directory for a worked write-review loop (iteration 1 fails, iteration 2 passes with feedback) and what spec-write sees on re-dispatch.

## Anti-Rationalization Rules

- Thinking "spec-review found minor issues, I should pass it anyway"? Stop. You check status, not severity. `"failed"` means re-dispatch spec-write. Only `"passed"` exits the cycle.
- Thinking "I should read the spec content to understand what went wrong"? Stop. You route on status. spec-write reads the review feedback, not you.
- Thinking "derive-intent failed, I should try running spec-write anyway"? Stop. spec-write requires intent.json. No intent, no spec.
- Thinking "5 iterations seems excessive, I should stop at 3"? Stop. The budget is 5. Convergence is spec-write and spec-review's concern, not yours.
- Thinking "I should detect that this is a guidance-resume run and rearrange iterations/"? Stop. run-process-change does that move before re-dispatching you. Whatever state is on disk is the state you run with.

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
