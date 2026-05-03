---
name: run-process-change
description: Phase orchestrator for the Process Change phase. Handles new-run vs resume detection, dispatches run-spec-refinement, run-implementation, run-build-check, impl-describe-flow (trust ON), and git-tool (pr) in sequence. Owns the human gates (spec approval, spec stuck, task 1 for decompose ON, PR review) and the PR rejection routing. Dispatched by run-strut.
---

# run-process-change

Process Change phase. Dispatched by run-strut. Shared context with run-strut.

Detect new-run vs resume, clean transient Process Change state on a new run, run the spec cycle (escalating to the spec_stuck gate if the iteration budget is exhausted), pause at the spec approval gate, run the implementation cycle (pausing at the task 1 gate for decompose ON), run build verification, open the PR, pause at the PR review gate, and handle PR rejection routing. Return to run-strut with a passed/failed/aborted result once the human merges or aborts.

This is the largest orchestrator — it owns both human gates and the rejection-path router. Every reasoning step is delegated to a sub-orchestrator or agent.

## Dispatches

- run-spec-refinement (sub-orchestrator skill) — once per new run, re-dispatched on PR rejection with `loop_target: "spec"`.
- run-implementation (sub-orchestrator skill) — once per approved spec, re-dispatched on PR rejection with `loop_target: "implementation"`.
- run-build-check (sub-orchestrator skill) — once per implementation success.
- impl-describe-flow (agent) — trust ON only. Once, after run-build-check passes, before git-tool (pr).
- git-tool (agent, mode `pr`) — once, after run-build-check passes (or after impl-describe-flow if trust ON).

## Input Contract

### Files Read (for routing only)

- `.strut-pipeline/classification.json` — routing source of truth. `what` is compared against any prior state's `what` to decide new-run vs resume. `modifiers.trust` is read to conditionally dispatch impl-describe-flow (Step 9). `modifiers.decompose` is read for the task 1 gate routing (Step 7b).
- `.strut-pipeline/process-change-state.json` — phase-level resume state. Read on every invocation to decide whether to start fresh or resume.
- `.strut-pipeline/spec-refinement/spec-review.json` — status check after run-spec-refinement.
- `.strut-pipeline/spec-refinement/spec-refinement-result.json` — existence + status check after run-spec-refinement. Only present when run-spec-refinement exhausts its 5-iteration budget; signals routing to the spec_stuck gate.
- `.strut-pipeline/spec-refinement/spec.json` — content read at the spec approval gate (Step 6) AND the adversarial spec attack gate (Step 6b) to render a human-readable summary, plus existence check and `what` reference for state writes. Content fields are NOT used for routing decisions — only for human display, consistent with the "route on status alone" rule.
- `.strut-pipeline/spec-refinement/iterations/iter-*-review.json` — content read at the spec_stuck gate (Step 5b) to render one-line summaries of each failed iteration. Display only.
- `.strut-pipeline/implementation/implementation-status.json` — status check after run-implementation.
- `.strut-pipeline/build-check/build-result.json` — status check after run-build-check.
- `.strut-pipeline/impl-describe-flow.txt` — existence check after impl-describe-flow (trust ON only).
- `.strut-pipeline/git-pr-result.json` — status check after git-tool (pr).

### Other Inputs

- The human's change request, available from run-strut via conversation context.
- On resume after a gate, the human's response given when re-invoking `/run-strut`: one of `continue`, `approve`, `revise`, `reject implementation <feedback>`, `reject spec <feedback>`, `abort`, `merged`. Parsed only at gate boundaries; never consulted mid-phase.

### Prerequisite Files

- `.strut-pipeline/classification.json` must exist with `status: "classified"`. Produced by Read Truth.

If missing or malformed, overwrite `process-change-state.json` with `status: "failed"`, `failed_at: "prerequisites"`, and a summary naming the specific problem. Stop.

## Output Contract

### Result File

- `.strut-pipeline/process-change-state.json`

Written on every gate pause, every resume decision, and every terminal outcome. The single file run-strut reads to decide what to do next and the single file read on re-invocation to resume.

### Result Schema

Gate pause (spec approval):

```json
{
  "skill": "run-process-change",
  "status": "blocked",
  "gate": "spec_approval",
  "what": "<from classification.json>",
  "completed": ["spec_refinement"],
  "next": "implementation"
}
```

Gate pause (spec_stuck — fires when run-spec-refinement exhausts its 5-iteration budget; valid resume responses are `guidance: <text>` and abort):

```json
{
  "skill": "run-process-change",
  "status": "blocked",
  "gate": "spec_stuck",
  "what": "<from classification.json>",
  "iterations_attempted": 5,
  "iterations_dir": ".strut-pipeline/spec-refinement/iterations/",
  "completed": [],
  "next": "spec_refinement"
}
```

Gate pause (task_1 — fires on decompose ON after task 1's TDD cycle completes; valid resume responses are continue and abort):

```json
{
  "skill": "run-process-change",
  "status": "blocked",
  "gate": "task_1",
  "what": "<from classification.json>",
  "completed": ["spec_refinement", "task_1"],
  "next": "implementation_remaining",
  "start_task": "<first remaining task id, e.g. task-2>"
}
```

Gate pause (adversarial_spec_attack — fires only when both trust_on and decompose_on are true, i.e. guarded-decompose path; valid resume responses are continue and abort):

```json
{
  "skill": "run-process-change",
  "status": "blocked",
  "gate": "adversarial_spec_attack",
  "what": "<from classification.json>",
  "completed": ["spec_refinement"],
  "next": "step_7"
}
```

Gate pause (PR review):

```json
{
  "skill": "run-process-change",
  "status": "blocked",
  "gate": "pr_review",
  "what": "<from classification.json>",
  "completed": ["spec_refinement", "implementation", "build_check", "pr_opened"],
  "next": "awaiting_merge",
  "pr_url": "<from git-pr-result.json>"
}
```

Gate pause (PR rejection en route to re-dispatch):

```json
{
  "skill": "run-process-change",
  "status": "blocked",
  "gate": "pr_rejection",
  "loop_target": "implementation | spec",
  "feedback": "<verbatim human feedback>",
  "what": "<from classification.json>",
  "completed": ["spec_refinement"],
  "next": "implementation | spec_refinement"
}
```

Passed (human merged):

```json
{
  "skill": "run-process-change",
  "status": "passed",
  "what": "<from classification.json>",
  "completed": ["spec_refinement", "implementation", "build_check", "pr_opened", "merged"],
  "pr_url": "<from git-pr-result.json>"
}
```

Failed (any non-recoverable failure):

```json
{
  "skill": "run-process-change",
  "status": "failed",
  "failed_at": "<spec_refinement | implementation | build_check | describe_flow | pr | prerequisites>",
  "what": "<from classification.json or 'unknown'>",
  "completed": [],
  "summary": "<one line naming the specific failure and the referenced result file>"
}
```

Aborted (human aborted at a gate):

```json
{
  "skill": "run-process-change",
  "status": "aborted",
  "aborted_at": "<gate name>",
  "what": "<from classification.json>",
  "completed": [...]
}
```

### Status Values

- `blocked` — phase paused at a human gate. Never returned to run-strut as a terminal; run-strut interprets `blocked` as "exit and wait for human re-invocation".
- `passed` — phase complete, PR merged, ready for Update Truth.
- `failed` — any sub-orchestrator or agent produced `failed` or no output. Terminal. run-strut escalates to the human.
- `aborted` — human chose to stop at a gate. Terminal.

No other status values.

### Return to run-strut

- On `blocked`: exit. Human re-invokes `/run-strut` to resume.
- On `passed`: run-strut dispatches run-update-truth.
- On `failed` or `aborted`: run-strut reports to the human and stops.

## Dispatch Sequence

### Step 1: Setup

```bash
mkdir -p .strut-pipeline
```

Do not `rm -f .strut-pipeline/process-change-state.json` here — the resume branch in Step 2 must read it. Step 3 owns cleanup for the new-run branch.

### Step 2: Verify prerequisites and detect new-run vs resume

Check `.strut-pipeline/classification.json` exists and is parseable JSON with `status: "classified"` and a non-empty `what`. If missing or malformed, overwrite `process-change-state.json` with `status: "failed"`, `failed_at: "prerequisites"`, and a summary naming the problem. Stop.

Read `classification.json.what` → `current_what`. Read `classification.json.modifiers.trust` → `trust_on` (boolean).

Check `.strut-pipeline/process-change-state.json` — if the only content is the Step 1 placeholder (or the file is missing prior to Step 1's write), treat as new run. Otherwise, read its `what` field → `prior_what`.

- If `prior_what` is missing, `"unknown"`, or does not match `current_what` → this is a **new run**. Go to Step 3.
- If `prior_what == current_what` → this is a **resume**. Read `status`, `gate`, `completed`, and `next`. Go to Step 4.

### Step 3: New-run cleanup

Remove transient Process Change state. Do not remove Read Truth outputs or classification-log.md.

```bash
rm -rf .strut-pipeline/spec-refinement
rm -rf .strut-pipeline/implementation
rm -rf .strut-pipeline/build-check
rm -f .strut-pipeline/git-pr-result.json
rm -f .strut-pipeline/impl-describe-flow.txt
rm -f .strut-pipeline/pr-rejection-feedback.json
```

Do not remove:
- `.strut-pipeline/classification.json`
- `.strut-pipeline/classification-log.md`
- `.strut-pipeline/impact-scan.md`
- `.strut-pipeline/truth-repo-impact-scan-result.json`
- `.strut-pipeline/update-truth/` (owned by the separate Update Truth phase)

Overwrite `process-change-state.json` with a fresh new-run record:

```json
{
  "skill": "run-process-change",
  "status": "blocked",
  "gate": null,
  "what": "<current_what>",
  "completed": [],
  "next": "spec_refinement"
}
```

Continue to Step 5 (Spec Refinement).

### Step 4: Resume dispatch

Based on the resume state's `next` field:

- `next == "spec_refinement"` and `gate == "spec_stuck"` → spec_stuck gate resume. Case-insensitive match on the leading prefix of the response:
  - `guidance:` followed by **non-empty clarifying text** — strip the `guidance:` prefix and any leading whitespace; if the resulting text is empty or whitespace-only, fall through to the unrecognized-response branch.
    1. Determine the next round number by listing `.strut-pipeline/spec-refinement/iterations-archive/` — `next_round = (count of existing round-* directories) + 1`. If `iterations-archive/` does not exist, `next_round = 1`.
    2. Move `.strut-pipeline/spec-refinement/iterations/` to `.strut-pipeline/spec-refinement/iterations-archive/round-<next_round>/`. Use `mkdir -p .strut-pipeline/spec-refinement/iterations-archive` first if needed, then `mv` the directory.
    3. Recreate an empty `iterations/` directory: `mkdir -p .strut-pipeline/spec-refinement/iterations`.
    4. Write `.strut-pipeline/spec-refinement/human-guidance.md` with the verbatim text after `guidance:` (no extra processing).
    5. Remove `spec-refinement-result.json` so the re-dispatched run-spec-refinement starts fresh: `rm -f .strut-pipeline/spec-refinement/spec-refinement-result.json`.
    6. Go to Step 5 (re-dispatch run-spec-refinement). The sub-orchestrator counts fresh iterations from the now-empty directory; spec-write reads `human-guidance.md` (top priority) and the `iterations-archive/round-*/` history.
  - `abort` → write `aborted` state with `aborted_at: "spec_stuck"`, say `Pipeline aborted at spec_stuck gate.`, stop.
  - anything else (including empty response, conversational phrases, `guidance` without a colon, or `guidance:` with no text after it) → say `Unrecognized response. Use "guidance: <non-empty text>" or abort.` Stop without modifying state.
- `next == "spec_refinement"` → go to Step 5. (Rare — only if the prior invocation exited before dispatching run-spec-refinement.)
- `next == "implementation"` and `gate == "spec_approval"` → this is a spec-approval-gate resume. Case-insensitive literal match on the first word:
  - `continue` or `approve` → go to Step 6b (Adversarial Spec Attack check). Step 6b conditionally fires the adversarial gate on guarded-decompose, or falls through to Step 7.
  - `revise` → go to Step 6 (re-dispatch run-spec-refinement; spec-write reads the existing `spec-review.json` as feedback per its own input contract).
  - `abort` → write `aborted` state with `aborted_at: "spec_approval"`, stop.
  - anything else (including empty, conversational phrases like "yes" / "sure" / "looks good", or questions) → say `Unrecognized response. Use continue, revise, or abort.` Stop without modifying state.
- `next == "step_7"` and `gate == "adversarial_spec_attack"` → this is an adversarial-spec-attack-gate resume. Case-insensitive literal match on the first word:
  - `continue` → go to Step 7 (Implementation).
  - `abort` → write `aborted` state with `aborted_at: "adversarial_spec_attack"`, say `Pipeline aborted at adversarial_spec_attack.`, stop.
  - anything else (including empty, conversational phrases, or questions) → say `Unrecognized response. Use continue or abort.` Stop without modifying state.
- `next == "implementation_remaining"` and `gate == "task_1"` → this is a task-1-gate resume. Case-insensitive literal match on the first word:
  - `continue` → go to Step 7, passing `start_task` from the state file as `args` to run-implementation so it resumes from that task.
  - `abort` → write `aborted` state with `aborted_at: "task_1"`, say `Pipeline aborted at task_1 gate.`, stop.
  - anything else (including empty, conversational phrases, or questions) → say `Unrecognized response. Use continue or abort.` Stop without modifying state.
- `next == "implementation"` and `gate == "pr_rejection"` with `loop_target == "implementation"` → go to Step 7. impl-write-code reads `.strut-pipeline/pr-rejection-feedback.json` as its feedback source on this re-dispatch. (See Step 11 for how that file is written.)
- `next == "spec_refinement"` and `gate == "pr_rejection"` with `loop_target == "spec"` → go to Step 5 after wiping implementation state. See Step 11.
- `next == "awaiting_merge"` and `gate == "pr_review"` → this is a PR-gate resume. Case-insensitive literal match on the first word (or first two words for `reject ...`). This gate writes a terminal `passed` state — strict matching is critical.
  - `merged` → write `passed` state with `completed` appending `"merged"`, stop (return to run-strut).
  - `reject implementation` (followed by feedback text) → write rejection state targeting implementation (Step 11). Go to Step 7.
  - `reject spec` (followed by feedback text) → write rejection state targeting spec (Step 11). Go to Step 5 after wipe.
  - `abort` → write `aborted` state with `aborted_at: "pr_review"`, stop.
  - anything else (including empty, "lgtm", "ship it", "looks good", "yes", bare `reject` without a target, or questions) → say `Unrecognized response. Use merged, reject implementation <feedback>, reject spec <feedback>, or abort.` Stop without modifying state.

- `gate == "step_pause"` → step-mode-pause resume. Read `next` and route: `"build_check"` → Step 8, `"describe_flow"` → Step 9, `"pr"` → Step 10. Case-insensitive first word:
  - `continue` → go to the step indicated by `next`.
  - `abort` → write `aborted` state with `aborted_at: "step_pause"`, stop.
  - anything else → say `Unrecognized response. Use continue or abort.` Stop without modifying state.

If `completed` already contains a stage name, Step 5 / 7 / 8 / 9 / 10 each check their own completion and skip if the stage already produced a passed result file. This keeps resume idempotent without the orchestrator reasoning about content.

### Step 5: Dispatch run-spec-refinement

Skip this step if `completed` already includes `spec_refinement` AND `.strut-pipeline/spec-refinement/spec-review.json` has `status: "passed"`. Otherwise dispatch.

Dispatch the run-spec-refinement skill via the Skill tool. No `args` needed — it reads the change request from conversation context and pipeline state.

When the sub-orchestrator returns, route in this order:

1. **Check for exhaustion first.** Does `.strut-pipeline/spec-refinement/spec-refinement-result.json` exist?
   - **Yes**: Read ONLY the `status` field.
     - `"exhausted"` → run-spec-refinement burned its 5-iteration budget. Go to Step 5b (spec_stuck gate).
     - any other status → unexpected; treat as failure: overwrite `process-change-state.json` with `status: "failed"`, `failed_at: "spec_refinement"`, summary referencing the result file. Stop.
   - **No**: continue to step 2 below.

2. **Check spec-review.json.** Does it exist?
   - **Yes:** Read ONLY the `status` field.
     - `"passed"` → append `"spec_refinement"` to `completed`. Continue to Step 6.
     - `"failed"` → overwrite `process-change-state.json` with `status: "failed"`, `failed_at: "spec_refinement"`, and a summary referencing `.strut-pipeline/spec-refinement/spec-review.json`. Stop.
   - **No:** Overwrite `process-change-state.json` with `status: "failed"`, `failed_at: "spec_refinement"`, and a summary naming the missing output. Stop.

### Step 5b: Gate — spec_stuck (run-spec-refinement exhausted its budget)

This step runs only when `spec-refinement-result.json` reports `status: "exhausted"`. The 5-iteration budget for the current round expired without a passing spec.

Read `iterations_attempted` from `spec-refinement-result.json`.

Build iteration summaries for display: for each `.strut-pipeline/spec-refinement/iterations/iter-*-review.json` (in numeric order by iteration), extract a one-line summary. Prefer the review's `summary` field; if absent or empty, synthesize a one-liner from the first entry of `review_issues[]` or `validation_issues[]` (e.g., `"<criterion_id>: <issue>"`). Render only — do not analyze or aggregate further.

Overwrite `.strut-pipeline/process-change-state.json` with:

```json
{
  "skill": "run-process-change",
  "status": "blocked",
  "gate": "spec_stuck",
  "what": "<current_what>",
  "iterations_attempted": <from result file>,
  "iterations_dir": ".strut-pipeline/spec-refinement/iterations/",
  "completed": [],
  "next": "spec_refinement"
}
```

Say:

```
─────────────────────────────────────
SPEC STUCK GATE
─────────────────────────────────────
<N> iterations attempted; none passed review.

Iteration history:
  Iter 1 — <one-line summary from iter-1-review.json>
  Iter 2 — <one-line summary>
  ...
  Iter <N> — <one-line summary>

The spec-write/spec-review loop did not converge automatically. Human input
can break the impasse — for example, restricting scope, accepting a concern,
or redirecting the approach.

Iteration files (for deeper inspection):
  .strut-pipeline/spec-refinement/iterations/

Respond at the next /run-strut invocation:
  - "guidance: <text>"   — clarifying input. Spec refinement re-runs for up to
                            5 more iterations with your guidance as the
                            highest-priority input. Example:
                            "guidance: scope excludes inheritance criterion."
  - "abort"              — stop the pipeline.
─────────────────────────────────────
```

Stop. Do not proceed. Do not ask anything beyond the prompt above.

### Step 6: Gate 1 — Spec Approval

Overwrite `.strut-pipeline/process-change-state.json` with:

```json
{
  "skill": "run-process-change",
  "status": "blocked",
  "gate": "spec_approval",
  "what": "<current_what>",
  "completed": ["spec_refinement"],
  "next": "implementation"
}
```

Before displaying the gate:

1. **Check for scope mismatch between classification and spec.** Collect any of these notes for inclusion in the prompt:
   - If `classification.json.modifiers.trust` is OFF but `spec.json.criteria[]` contains any `type: "negative"` entries, add: `⚠ Spec contains negative criteria but trust is OFF. Consider overriding to trust ON.`
   - If `classification.json.modifiers.decompose` is OFF but `spec.json.implementation_notes.files_to_modify` spans 3+ distinct directory roots, add: `⚠ Spec touches N directory boundaries but decompose is OFF. Consider overriding to decompose ON.`

2. **Read `.strut-pipeline/spec-refinement/spec.json` and render a human-readable summary.** The spec is a JSON file contract for downstream agents, but at this gate the human needs to review the actual content, not navigate raw JSON. Render the approval-relevant fields below in full — `what`, `user_sees`, `criteria`, `implementation_notes.files_to_modify`, `out_of_scope`, `tasks`. Do not truncate. Implementation hints (`patterns_to_follow`, `files_to_reference`) are not rendered here — they're for downstream agents, not approval, and the user can read them via the raw spec link if curious.

Render rules for missing or empty fields:
- If a field is missing entirely, omit its section silently.
- If an array field exists but is empty, render `(none specified)` under the section header.
- If `criteria[].type` is absent on an entry, render the type as `unspecified`.
- If `tasks` is missing or has 0 entries, render `Tasks: (not specified — single-task default).`

Say (with bracketed sections filled from the actual spec content):

```
─────────────────────────────────────
SPEC APPROVAL GATE
─────────────────────────────────────

**What:** <spec.what>

**User sees:**
<spec.user_sees>

**Acceptance criteria** (<count> total: <positive count> positive, <negative count> negative):
- **C1** (<type>): Given <given>, when <when>, then <then>.
- **C2** (<type>): ...
  [render every criterion in spec.criteria, in order]

**Files to modify** (<count>):
- `<path>` — <reason>
  [render every entry in spec.implementation_notes.files_to_modify]

**Out of scope:**
- <item>
  [render every entry in spec.out_of_scope; if empty, write "(none specified)"]

**Tasks:** <count> task(s).
  [if more than 1, render each task's description on its own bulleted line]

[scope mismatch notes from step 1, if any — each on its own line, prefixed with ⚠]

─────────────────────────────────────
Raw files (for deeper review):
  Spec:    .strut-pipeline/spec-refinement/spec.json
  Intent:  .strut-pipeline/spec-refinement/intent.json
  Review:  .strut-pipeline/spec-refinement/spec-review.json

Respond at the next /run-strut invocation:
  - "continue" to approve and proceed to implementation
  - "revise" to re-run spec refinement with feedback (edit spec-review.json first, or provide notes inline)
  - "abort" to stop the pipeline
─────────────────────────────────────
```

Stop. Do not proceed. Do not ask anything beyond the prompt above.

### Step 6b: Gate 1b — Adversarial Spec Attack (guarded-decompose only)

This step runs only when both trust_on and decompose_on are true (guarded-decompose path). If either modifier is OFF, skip directly to Step 7.

When both modifiers are ON, overwrite `.strut-pipeline/process-change-state.json` with:

```json
{
  "skill": "run-process-change",
  "status": "blocked",
  "gate": "adversarial_spec_attack",
  "what": "<current_what>",
  "completed": ["spec_refinement"],
  "next": "step_7"
}
```

Render the spec for the user, using the same approach as Step 6's spec approval gate. Read `.strut-pipeline/spec-refinement/spec.json` and render `what`, `user_sees`, `criteria`, `implementation_notes.files_to_modify`, `out_of_scope`, and `tasks` in full. Implementation hints (`patterns_to_follow`, `files_to_reference`) are not rendered — they're for downstream agents.

Render rules for missing or empty fields (identical to Step 6):
- If a field is missing entirely, omit its section silently.
- If an array field exists but is empty, render `(none specified)` under the section header.
- If `criteria[].type` is absent on an entry, render the type as `unspecified`.
- If `tasks` is missing or has 0 entries, render `Tasks: (not specified — single-task default).`

The user is about to scrutinize this spec adversarially in a separate session — they need to see what they're attacking.

Say (with bracketed sections filled from the actual spec content):

```
─────────────────────────────────────
ADVERSARIAL SPEC ATTACK GATE
─────────────────────────────────────

**What:** <spec.what>

**User sees:**
<spec.user_sees>

**Acceptance criteria** (<count> total: <positive count> positive, <negative count> negative):
- **C1** (<type>): Given <given>, when <when>, then <then>.
- **C2** (<type>): ...
  [render every criterion in spec.criteria, in order]

**Files to modify** (<count>):
- `<path>` — <reason>
  [render every entry in spec.implementation_notes.files_to_modify]

**Out of scope:**
- <item>
  [render every entry in spec.out_of_scope; if empty, write "(none specified)"]

**Tasks:** <count> task(s).
  [if more than 1, render each task's description on its own bulleted line]

─────────────────────────────────────

The pipeline has paused for the adversarial spec attack checkpoint. In a
separate session, probe the spec above for weaknesses before any code is
written. Look for: trust-boundary gaps, ambiguous criteria an attacker
could exploit, missing must_never coverage, scope creep that opens new
risk surface.

Raw files (for deeper review):
  Spec:    .strut-pipeline/spec-refinement/spec.json
  Intent:  .strut-pipeline/spec-refinement/intent.json
  Review:  .strut-pipeline/spec-refinement/spec-review.json

Respond at the next /run-strut invocation:
  - "continue" to proceed to implementation
  - "abort" to stop the pipeline
─────────────────────────────────────
```

Stop. Do not proceed to Step 7 until the human resumes.

### Step 7: Dispatch run-implementation

Skip this step if `completed` already includes `implementation` AND `.strut-pipeline/implementation/implementation-status.json` has `status: "passed"`. Otherwise dispatch.

Dispatch the run-implementation skill via the Skill tool. If resuming from the task_1 gate (i.e., the current `process-change-state.json` has `gate: "task_1"` and a `start_task` field), pass `args: "<start_task>"` so run-implementation resumes from that task. Otherwise, no `args` needed (run-implementation defaults to `task-1`).

When the sub-orchestrator returns, check: does `.strut-pipeline/implementation/implementation-status.json` exist?

- **Yes:** Read ONLY the `status` field.
  - `"passed"` → append `"implementation"` to `completed`.
    **Step pause.** If `.strut-pipeline/step-mode` exists, say `STEP: run-implementation — passed. Output: .strut-pipeline/implementation/implementation-status.json. Next: run-build-check.` Ask `Continue? (yes / abort)` and wait. If `abort`, overwrite `process-change-state.json` with `status: "blocked"`, `gate: "step_pause"`, `completed` (current value), `next: "build_check"`, and stop.
    Continue to Step 8.
  - `"blocked"` → read `gate` from the same file. If `gate == "task_1"`: also read `remaining_tasks` and `branch_name`. Go to Step 7b.
  - `"failed"` → overwrite `process-change-state.json` with `status: "failed"`, `failed_at: "implementation"`, and a summary referencing `.strut-pipeline/implementation/implementation-status.json`. Stop.
- **No:** Overwrite `process-change-state.json` with `status: "failed"`, `failed_at: "implementation"`, and a summary naming the missing output. Stop.

### Step 7b: Gate — Task 1 Validation (decompose ON only)

This step is reached only when run-implementation returns `status: "blocked"` with `gate: "task_1"`. Standard path never reaches this step.

Overwrite `.strut-pipeline/process-change-state.json` with:

```json
{
  "skill": "run-process-change",
  "status": "blocked",
  "gate": "task_1",
  "what": "<current_what>",
  "completed": ["spec_refinement", "task_1"],
  "next": "implementation_remaining",
  "start_task": "<remaining_tasks[0]>"
}
```

Say:

```
─────────────────────────────────────
TASK 1 GATE
─────────────────────────────────────
Task 1 committed on branch: <branch_name>
Remaining tasks: <remaining_tasks, comma-separated>

Review the task-1 diff. If the AI's interpretation is wrong,
abort and clarify the spec before retrying.

Respond at the next /run-strut invocation:
  - "continue" to proceed with remaining tasks
  - "abort" to stop the pipeline
─────────────────────────────────────
```

Stop. Do not proceed. Do not ask anything beyond the prompt above.

### Step 8: Dispatch run-build-check

Skip this step if `completed` already includes `build_check` AND `.strut-pipeline/build-check/build-result.json` has `status: "passed"`. Otherwise dispatch.

Dispatch the run-build-check skill via the Skill tool. No `args` needed.

When the sub-orchestrator returns, check: does `.strut-pipeline/build-check/build-result.json` exist?

- **Yes:** Read ONLY the `status` field.
  - `"passed"` → append `"build_check"` to `completed`.
    **Step pause.** If `.strut-pipeline/step-mode` exists, say `STEP: run-build-check — passed. Output: .strut-pipeline/build-check/build-result.json. Next: [impl-describe-flow if trust ON, otherwise git-tool (pr)].` Ask `Continue? (yes / abort)` and wait. If `abort`, overwrite `process-change-state.json` with `status: "blocked"`, `gate: "step_pause"`, `completed` (current value), `next: "describe_flow"`, and stop.
    Continue to Step 9.
  - `"failed"` → overwrite `process-change-state.json` with `status: "failed"`, `failed_at: "build_check"`, and a summary referencing `.strut-pipeline/build-check/build-result.json`. Stop.
- **No:** Overwrite `process-change-state.json` with `status: "failed"`, `failed_at: "build_check"`, and a summary naming the missing output. Stop.

### Step 9: Dispatch impl-describe-flow (trust ON only)

This step runs only when `trust_on` is true. If `trust_on` is false, skip to Step 10.

Skip this step if `completed` already includes `describe_flow` AND `.strut-pipeline/impl-describe-flow.txt` exists and is non-empty. Otherwise dispatch.

Dispatch the impl-describe-flow agent via the Agent tool with `subagent_type: "impl-describe-flow"`.

When the agent returns, check: does `.strut-pipeline/impl-describe-flow.txt` exist and is it non-empty?

- **Yes:** Append `"describe_flow"` to `completed`.
    **Step pause.** If `.strut-pipeline/step-mode` exists, say `STEP: impl-describe-flow — done. Output: .strut-pipeline/impl-describe-flow.txt. Next: git-tool (pr).` Ask `Continue? (yes / abort)` and wait. If `abort`, overwrite `process-change-state.json` with `status: "blocked"`, `gate: "step_pause"`, `completed` (current value), `next: "pr"`, and stop.
    Continue to Step 10.
- **No:** Overwrite `process-change-state.json` with `status: "failed"`, `failed_at: "describe_flow"`, and a summary naming the missing output. Stop.

### Step 10: Dispatch git-tool (pr)

Skip this step if `completed` already includes `pr_opened` AND `.strut-pipeline/git-pr-result.json` has `status: "opened"`. Otherwise dispatch.

Dispatch the git-tool agent via the Agent tool with `subagent_type: "git-tool"` and `prompt: "pr"`.

When the agent returns, check: does `.strut-pipeline/git-pr-result.json` exist?

- **Yes:** Read ONLY the `status` field (and `pr_url` for state).
  - `"opened"` → append `"pr_opened"` to `completed`. Continue to Step 11 (Gate 2).
  - `"failed"` → overwrite `process-change-state.json` with `status: "failed"`, `failed_at: "pr"`, and a summary referencing `.strut-pipeline/git-pr-result.json`. Stop.
- **No:** Overwrite `process-change-state.json` with `status: "failed"`, `failed_at: "pr"`, and a summary naming the missing output. Stop.

### Step 11: Gate 2 — PR Review (and rejection routing)

Read `.strut-pipeline/git-pr-result.json` for `pr_url`.

Overwrite `.strut-pipeline/process-change-state.json` with:

```json
{
  "skill": "run-process-change",
  "status": "blocked",
  "gate": "pr_review",
  "what": "<current_what>",
  "completed": ["spec_refinement", "implementation", "build_check", "describe_flow (trust ON only)", "pr_opened"],
  "next": "awaiting_merge",
  "pr_url": "<pr_url>"
}
```

Say:

```
─────────────────────────────────────
PR REVIEW GATE
─────────────────────────────────────
PR: <pr_url>

Review the PR on GitHub. Respond at the next /run-strut invocation:
  - "merged" (after merging the PR) to proceed to Update Truth
  - "reject implementation <feedback>" to re-run implementation with feedback
  - "reject spec <feedback>" to wipe implementation and re-run spec refinement
  - "abort" to stop the pipeline
─────────────────────────────────────
```

Stop.

**Rejection routing (executed only on resume from this gate; see Step 4). Rejection also cleans up `impl-describe-flow.txt` — see the `rm -f` lists below.**

- `reject implementation <feedback>`:
  1. Write `.strut-pipeline/pr-rejection-feedback.json` with `{"loop_target":"implementation","feedback":"<verbatim text>","from":"pr_review"}`. impl-write-code reads this file as its feedback source on this re-dispatch (per its own input contract).
  2. Overwrite `process-change-state.json` with `status: "blocked"`, `gate: "pr_rejection"`, `loop_target: "implementation"`, `feedback: "<text>"`, `completed: ["spec_refinement"]`, `next: "implementation"`.
  3. Remove per-task implementation artifacts: for each `task-*` directory under `.strut-pipeline/implementation/`, remove `impl-write-code-result.json`, `review-scope.json`, `review-criteria-eval.json`, `review-security.json`, `review-chain-result.json`, and `git-commit-result.json`. Also remove `.strut-pipeline/implementation/implementation-status.json`, `.strut-pipeline/implementation/active-task.json`, `.strut-pipeline/build-check/build-result.json`, `.strut-pipeline/impl-describe-flow.txt`, `.strut-pipeline/git-pr-result.json`. Keep `tests-result.json` and `git-branch-result.json` — tests and branch survive an implementation-only rejection.
  4. Go to Step 7.

- `reject spec <feedback>`:
  1. Write `.strut-pipeline/pr-rejection-feedback.json` with `{"loop_target":"spec","feedback":"<verbatim text>","from":"pr_review"}`. spec-write reads this on re-dispatch.
  2. Overwrite `process-change-state.json` with `status: "blocked"`, `gate: "pr_rejection"`, `loop_target: "spec"`, `feedback: "<text>"`, `completed: []`, `next: "spec_refinement"`.
  3. Wipe implementation-side state: `rm -rf .strut-pipeline/implementation .strut-pipeline/build-check` and `rm -f .strut-pipeline/git-pr-result.json .strut-pipeline/impl-describe-flow.txt`. Do not wipe `.strut-pipeline/spec-refinement` — spec-write reads the prior spec and the rejection feedback to revise.
  4. Go to Step 5.

- `abort`: overwrite `process-change-state.json` with `status: "aborted"`, `aborted_at: "pr_review"`. Stop.

### Step 12: Merged — terminal passed

Only reached from Step 4 when the human responds `merged` to the PR review gate.

Overwrite `.strut-pipeline/process-change-state.json` with:

```json
{
  "skill": "run-process-change",
  "status": "passed",
  "what": "<current_what>",
  "completed": ["spec_refinement", "implementation", "build_check", "describe_flow (trust ON only)", "pr_opened", "merged"],
  "pr_url": "<pr_url from git-pr-result.json>"
}
```

Say `Process Change complete. PR merged. Returning to run-strut.` Return.

## Examples

Read `examples.md` in this skill's directory for worked examples of gate response parsing and rejection routing file cleanup.

## Anti-Rationalization Rules

- Thinking "the human didn't respond at the gate, I should guess they meant 'continue' to save them time"? Stop. Gates block. Silence exits the skill. Only an explicit response on the next invocation moves past a gate.
- Thinking "run-spec-refinement returned failed, I should re-dispatch it with different framing"? Stop. Sub-orchestrators own their retry budgets. A `failed` from a sub-orchestrator is terminal at this level. Write `failed` and stop.
- Thinking "run-implementation failed on retries exhausted but the feedback looks addressable, one more cycle would do it"? Stop. run-implementation's 3-retry budget is the budget. You do not extend it. Escalate.
- Thinking "build-check failed — I should tweak the test file to make it pass"? Stop. You do not modify source, test, or spec files. You dispatch. Sub-orchestrators and agents modify files.
- Thinking "the PR body is thin — I should add more context before opening"? Stop. git-tool composes the PR body from spec.json per its contract. You do not prepare, decorate, or edit PR content.
- Thinking "the human rejected the PR with implementation feedback but their note actually points at a spec issue — I'll route it to spec refinement"? Stop. You route by the human's explicit `loop_target` in their response (`reject implementation` vs `reject spec`). The human decides where the loop lands. You do not reinterpret.
- Thinking "the resume state's `what` is similar to the current `what` but not identical — probably safe to resume"? Stop. Match is exact. If different, new run. Partial matches are new runs.
- Thinking "the human said 'abort' at the spec gate, but the spec looks fine — I should confirm once before stopping"? Stop. `abort` is terminal. You do not request confirmation. Write the aborted state and stop.
- Thinking "I should read spec.json or the diff to summarize at the gate prompts"? Stop. Gate prompts list file paths. The human opens the files. You do not format or summarize content.
- Thinking "the rejection path is complex — I'll just re-run the whole phase from the top"? Stop. Rejection routes by `loop_target`. `implementation` preserves tests and branch. `spec` preserves the spec workspace. Wiping the wrong files burns work the human did not ask to discard.
- Thinking "trust is ON but this change looks harmless — I'll skip impl-describe-flow to save time"? Stop. Trust ON means Step 9 runs. The classification stands. You do not evaluate whether the describe-flow step is warranted.
- Thinking "I should read spec.json's content to pass context to run-implementation"? Stop. Sub-orchestrators read their own inputs from file contracts. You do not pass content via conversation.
- Thinking "the state file is inconsistent with the files on disk — I should reconcile"? Stop. State and files can disagree only after a crash or manual edit. If a resume's `next` points at a stage whose output file is missing or failed, dispatch that stage fresh. Do not invent reconciliation logic beyond the per-step `completed` + file-status check.
- Thinking "task 1 passed review, the remaining tasks will be fine — I'll skip the task_1 gate to save time"? Stop. Decompose ON means the task_1 gate fires after task 1's commit. The classification stands. You do not evaluate whether the gate is warranted.
- Thinking "run-spec-refinement exhausted its budget but the latest spec looks acceptable to me — I'll skip the spec_stuck gate and proceed"? Stop. Exhaustion means the agents could not converge. The human decides whether to inject guidance, force-accept, or abort. You write the gate state and stop.
- Thinking "the human's `guidance:` text is vague — I should rewrite it before saving"? Stop. Write the verbatim text after `guidance:` to `human-guidance.md`. spec-write reads it. You do not edit, summarize, or interpret human input.

## Boundary Constraints

- Dispatch only: run-spec-refinement, run-implementation, run-build-check, impl-describe-flow (trust ON only), git-tool (pr). Decompose ON activates the task-1 gate routing in Steps 4 and 7b; the dispatch sequence itself is unchanged.
- Do not derive intent, write specs, review specs, write tests, write code, review code, run builds, cleanup build errors, commit, or open PRs itself. All of that is delegated.
- Do not read content fields from agent or sub-orchestrator result files beyond the declared routing fields (`status`, `pr_url`, and the `what` comparison from `classification.json`).
- Do not modify any source, test, spec, or pipeline file except `.strut-pipeline/process-change-state.json`, `.strut-pipeline/pr-rejection-feedback.json`, and (on spec_stuck guidance resume) `.strut-pipeline/spec-refinement/human-guidance.md` plus the `iterations/` → `iterations-archive/round-N/` move. Plus the explicit `rm -rf` / `rm -f` cleanups in Step 3 and Step 11.
- Do not scan the codebase. No `Grep`/`Glob`.
- Do not override modifiers. run-strut owns override. This skill reads classification.json as-is.
- Do not retry sub-orchestrators. Each sub-orchestrator owns its retry budget; a `failed` from one is terminal at this level.
- Do not merge PRs. Merge is the human's action at Gate 2.
- Do not delete `.strut-pipeline/classification.json`, `.strut-pipeline/classification-log.md`, `.strut-pipeline/impact-scan.md`, `.strut-pipeline/truth-repo-impact-scan-result.json`, or `.strut-pipeline/update-truth/`.
- Do not launch the Explore agent.

## Decompose ON behavior

Decompose ON activates per-task iteration inside run-implementation. This skill's top-level dispatch sequence is unchanged — it still dispatches run-implementation once. run-implementation internally loops per task.

**Task 1 gate (implemented):** After task 1's commit, run-implementation returns `status: "blocked"` with `gate: "task_1"`. Step 7 routes to Step 7b, which writes the task_1 gate state and pauses. On resume, Step 4 routes `next: "implementation_remaining"` back to Step 7, which passes `start_task` as args so run-implementation resumes from the next task.

**PR rejection cleanup (implemented):** Step 11's `reject implementation` path iterates all `task-*` directories under `.strut-pipeline/implementation/` rather than hardcoding `task-1`. Tests and branch survive; code/review/commit artifacts are removed across all tasks.

The standard path has exactly one task, so the task_1 gate branch never executes and the cleanup naturally degrades to one directory.
