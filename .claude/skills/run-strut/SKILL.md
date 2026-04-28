---
name: run-strut
description: Human entry point for the STRUT development pipeline. Receives a change request, orchestrates Read Truth → Process Change → Update Truth.
---

# run-strut

Human entry point. Invoked directly via `/run-strut`.

Receive a one-sentence change request via `$ARGUMENTS`, dispatch the phase orchestrators in sequence (Read Truth → Process Change → Update Truth), and present the classification at the override point. Phase orchestrators do the work.

## Dispatches

- run-read-truth (skill, built)
- run-process-change (skill, built)
- run-update-truth (skill, built)

## Input Contract

### Files Read

- `.pipeline/classification.json` — read after run-read-truth returns, to display the classification and support override edits.
- `.pipeline/process-change-state.json` — read on every invocation for resume detection. If `status: "blocked"`, this is a Process Change resume — skip Read Truth and the classification gate.

### Other Inputs

- `$ARGUMENTS` — on a new run: one natural-language sentence describing the change. On a resume: the human's gate response (e.g., `continue`, `abort`, `merged`, `reject implementation <feedback>`). The `--step` flag can appear anywhere — it enables step mode and is stripped before processing. If empty (after stripping `--step`), print context-appropriate usage and stop.

## Output Contract

### Result File

None.

### Files Modified on Override

When the human overrides a modifier at Step 4:

- `.pipeline/classification.json` — modifiers, `execution_path`, and `evidence.trust_rule` / `evidence.decompose_rule` are updated in place. The `status` field stays `classified`.
- `.pipeline/classification-log.md` — append-only. On override, append a new row with the same schema as the original, but prefix the path with `→` to mark the override. Never delete.

## Dispatch Sequence

### Step 1: Preflight check

Run this check before dispatching anything:

```bash
errors=""
check() {
  [ ! -e "$1" ] && errors="${errors}  $1\n"
}
check .claude/skills/run-read-truth/SKILL.md
check .claude/agents/truth-repo-impact-scan.md
check .claude/agents/truth-classify.md
check .claude/skills/run-process-change/SKILL.md
check .claude/skills/run-spec-refinement/SKILL.md
check .claude/skills/run-implementation/SKILL.md
check .claude/skills/run-build-check/SKILL.md
check .claude/agents/git-tool.md
check .claude/skills/run-update-truth/SKILL.md
check .claude/agents/update-capture.md
check .claude/rules/
if [ -n "$errors" ]; then
  printf "Preflight failed. Pipeline cannot start.\nMissing:\n%b" "$errors"
fi
```

If any `Missing:` lines printed, stop. Do not proceed to Step 2 with missing components.

If no errors, continue.

### Step 2: Resume detection

**Step mode:** If `$ARGUMENTS` contains `--step`, strip it and run `touch .pipeline/step-mode`. If `--step` is absent, run `rm -f .pipeline/step-mode`. Step mode is per-invocation — re-invoking without `--step` disables it.

Read `.pipeline/process-change-state.json` if it exists.

**If the file exists and `status == "blocked"`:** this is a Process Change resume.

- If `$ARGUMENTS` is empty, read `gate` from the state file and print the valid responses for that gate:
  - `gate == "spec_approval"`: `Specify a gate response: continue, revise, or abort.`
  - `gate == "adversarial_spec_attack"`: `Specify a gate response: continue (to proceed to implementation after performing the adversarial spec attack) or abort.`
  - `gate == "task_1"`: `Specify a gate response: continue (to proceed with remaining tasks) or abort.`
  - `gate == "pr_review"`: `Specify a gate response: merged, reject implementation <feedback>, reject spec <feedback>, or abort.`
  - `gate == "pr_rejection"`: `Specify a gate response: continue (to re-run with feedback) or abort.`
  - `gate == "step_pause"`: `Pipeline paused at step mode checkpoint. Specify a gate response: continue or abort.`
  - Any other gate value: `Specify a gate response. See .pipeline/process-change-state.json for current state.`
  - Stop.
- Print: `STRUT pipeline starting.\nResuming Process Change from [gate] gate.`
- Go to Step 5 (dispatch run-process-change).

**Otherwise** (no state file, or status is not `blocked`):

- If `$ARGUMENTS` is empty: say `What change are you making? Usage: /run-strut "your change description"` and stop.
- Print: `STRUT pipeline starting.\nChange: [ARGUMENTS]`
- Continue to Step 3.

### Step 3: Run Read Truth

Call the run-read-truth skill via the Skill tool. Pass the change request as input.

run-read-truth is a skill — it shares this context. It dispatches the scan and classify agents internally, checks their output files, and returns here when complete.

When run-read-truth returns, check: does `.pipeline/classification.json` exist?

- **Yes:** Continue to Step 4.
- **No:** run-read-truth should have reported the error. Stop.

### Step 4: Show classification and offer override

Read `.pipeline/classification.json` and display:

```
─────────────────────────────────────
CLASSIFICATION RESULT
─────────────────────────────────────
What:       [what]
What breaks: [what_breaks]

Modifiers:
  Trust:     [ON/OFF] — [evidence.trust_rule]
  Decompose: [ON/OFF] — [evidence.decompose_rule]

Execution path: [execution_path]
─────────────────────────────────────
```

Then ask:

```
Override? (or type "continue" to proceed)
  - "trust on" / "trust off" to change trust modifier
  - "decompose on" / "decompose off" to change decompose modifier
  - "split" if this should be two separate changes
  - "continue" to accept and proceed
```

Then stop and wait for the human to respond. Do not continue until they respond.

**How to interpret the human's response:**

- **Any affirmative or empty response:** Proceed to Step 5.
- **"trust on" or "trust off":** Update the trust modifier.
- **"decompose on" or "decompose off":** Update the decompose modifier.
- **"split":** Say `Split the change and run /run-strut separately for each part.` Stop.

**If the human changes a modifier:**

- Update `.pipeline/classification.json` with the new modifier values.
- Recalculate `execution_path` from the updated modifiers using the mapping declared in `.claude/agents/truth-classify.md` (single source of truth).
- Update the `trust_rule` or `decompose_rule` in `evidence` to note `Human override →`.
- Append an override row to `.pipeline/classification-log.md` with the updated values. Use the same table format as the original row, but prefix the path with `→` to indicate override. Example: `| 2026-04-14 | Add a spinner | OFF | ON | → standard-decompose | none | 0 (ui) |`
- Show the updated classification. Ask again (repeat Step 4 prompt).

### Step 5: Dispatch run-process-change

Call the run-process-change skill via the Skill tool. No `args` needed — it reads pipeline state from `.pipeline/` and the human's gate response (on resume) from conversation context.

run-process-change is a skill — it shares this context. It dispatches sub-orchestrators and agents internally, manages gates, and returns here when complete or blocked.

When run-process-change returns, read `.pipeline/process-change-state.json`:

- **`status == "blocked"`:** A gate was reached. run-process-change already printed the gate prompt. Print:
  ```
  Pipeline paused. Re-invoke /run-strut with your gate response.
  ```
  Stop.

- **`status == "passed"`:** Process Change complete — PR merged. Continue to Step 6.

- **`status == "failed"`:** Read `failed_at` and `summary`. Print:
  ```
  Process Change failed at [failed_at]: [summary]
  ```
  Stop.

- **`status == "aborted"`:** Read `aborted_at`. Print:
  ```
  Pipeline aborted at [aborted_at].
  ```
  Stop.

- **File missing or unparseable:** Print:
  ```
  Process Change did not produce a valid state file. Pipeline cannot continue.
  ```
  Stop.

### Step 6: Update Truth

Say: `Process Change complete. PR merged. Starting Update Truth.`

Call the run-update-truth skill via the Skill tool. No `args` needed — it reads pipeline state from `.pipeline/`.

run-update-truth is a skill — it shares this context. It dispatches update-capture, reads the result, presents proposals to the human, and returns here when complete.

When run-update-truth returns, run `rm -f .pipeline/step-mode`. Say:

```
Pipeline complete. Change merged and knowledge capture finished.
```

Stop.

## Examples

Read `examples.md` in this skill's directory for a worked override example (before/after classification.json) and the execution path matrix reference.

## Anti-Rationalization Rules

- Thinking "I should dispatch the scan agent directly to save a level of nesting"? Stop. run-strut calls phase orchestrators. Phase orchestrators dispatch agents. Two layers, no shortcuts.
- Thinking "I should start writing the spec since I can see the classification"? Stop. Process Change is a separate phase with its own orchestrator.
- Thinking "the classification looks wrong, I should re-run just the classify step"? Stop. Offer the human the override. If they want a re-run, they invoke `/run-strut` again.
- Thinking "I should read the scan results to give better context for the override decision"? Stop. The classification summary has what the human needs. They can read `.pipeline/impact-scan.md` themselves if they want details.
- Thinking "run-process-change returned blocked, I should continue anyway"? Stop. Blocked means a human gate was reached. Print the pause message and exit. The human re-invokes when ready.
- Thinking "I should parse the gate response myself before dispatching run-process-change"? Stop. run-process-change owns gate response parsing. Pass the conversation context through; do not interpret, validate, or reformat the human's gate response.
- Thinking "the resume state looks stale, I should clear it and start fresh"? Stop. run-process-change handles new-run vs resume detection. It compares `what` fields. You do not intervene in that logic.
- Thinking "Process Change failed, I should re-dispatch it"? Stop. A failed from a phase orchestrator is terminal at this level. Report to the human and stop. The human re-invokes `/run-strut` if they want to retry.

## Boundary Constraints

- Dispatch only: run-read-truth, run-process-change, run-update-truth.
- Do not scan the codebase. Agents inside run-read-truth do that.
- Do not classify. Agents inside run-read-truth do that.
- Do not write specs, tests, or code.
- Do not launch the Explore agent.
- Do not dispatch agents directly. Phase orchestrators handle agent dispatch.
- Do not delete `.pipeline/classification-log.md` — append-only per architecture.
- Do not delete or modify `.pipeline/process-change-state.json` — run-process-change owns that file.
- Do not parse or validate gate responses — run-process-change owns gate logic.
- No retry budget. If a phase fails, the human re-invokes `/run-strut`.
