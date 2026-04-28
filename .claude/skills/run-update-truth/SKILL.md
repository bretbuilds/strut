---
name: run-update-truth
description: Phase orchestrator for post-merge knowledge capture. Dispatches update-capture, reads the result, and presents proposals to the human. Runs in Update Truth, dispatched by run-strut.
---

# run-update-truth

Update Truth phase. Dispatched by run-strut. Shared context with run-strut.

Create the output directory, dispatch update-capture, read its result, and present proposals to the human. One agent, one dispatch, one result check. Do not analyze code or propose knowledge directly.

## Dispatches

- update-capture (agent)

## Input Contract

### Files Read

- `.pipeline/update-truth/knowledge-proposals.json` — status check only (after update-capture returns). Read `status` for routing, then read `proposals` and `summary` for display to the human.

### Other Inputs

None. No `$ARGUMENTS`. The agent reads all its inputs from `.pipeline/` files written by earlier phases.

### Prerequisite Files

The following files must exist from earlier phases (update-capture reads them):

- `.pipeline/classification.json`
- `.pipeline/spec-refinement/spec.json`

If these are missing, update-capture will report `failed` — this skill routes on that status.

## Output Contract

### Result File

None. Output is the file the dispatched agent writes:

- `.pipeline/update-truth/knowledge-proposals.json` (written by update-capture)

### Return to run-strut

On success: return with proposals displayed to the human. The human reviews and applies proposals outside the pipeline.

On failure: return with the failure reported. run-strut reports to the human.

## Dispatch Sequence

### Step 1: Setup

```bash
mkdir -p .pipeline/update-truth
rm -f .pipeline/update-truth/knowledge-proposals.json
```

### Step 2: Dispatch update-capture

Dispatch the update-capture agent via the Agent tool with `subagent_type: "update-capture"`. The prompt is `run`.

When the agent completes, check: does `.pipeline/update-truth/knowledge-proposals.json` exist and parse as JSON?

- **No (missing or malformed):** Say `Update-capture did not produce output. Check agent logs.` Return to run-strut with failure.
- **Yes:** Read the `status` field.
  - `"passed"` →
    **Step pause.** If `.pipeline/step-mode` exists, say `STEP: update-capture — passed. Output: .pipeline/update-truth/knowledge-proposals.json. Next: present proposals.` Ask `Continue? (yes / abort)` and wait. If `abort`, say `Pipeline stopped at step pause.` and stop.
    Continue to Step 3.
  - `"failed"` → read `summary`. Say `Update-capture failed: [summary]`. Return to run-strut with failure.
  - any other value → Say `Update-capture returned unexpected status: [status].` Return to run-strut with failure.

### Step 3: Present proposals to the human

Read `.pipeline/update-truth/knowledge-proposals.json` fully. Display proposals grouped by category:

```
─────────────────────────────────────
KNOWLEDGE PROPOSALS
─────────────────────────────────────
```

**Decision Log** (if any entries in `proposals.decision_log[]`):
For each entry, display `subject` and `entry`.

**System Map** (if any entries in `proposals.system_map[]`):
For each entry, display `change`.

**Rules** (if any entries in `proposals.rules[]`):
For each entry, display `target_file`, `proposed_rule`, `reason`, and `source`.

**Process Friction** (if any entries in `proposals.process_friction[]`):
For each entry, display `source`, `detail`, and `suggestion`.

If all proposal arrays are empty and process_friction is empty:
```
No knowledge capture warranted for this change.
```

If `root_cause` is not null (trust ON):
```
Root Cause Analysis:
[root_cause content]
```

End with:
```
─────────────────────────────────────
Review proposals above and apply manually where appropriate.
Pipeline complete.
─────────────────────────────────────
```

Say `Update Truth complete.` Return to run-strut.

## Anti-Rationalization Rules

- Thinking "I should analyze the diff myself to add proposals the agent missed"? Stop. The agent does the analysis. This skill dispatches and displays.
- Thinking "I should write the proposed rules directly to save time"? Stop. Proposals are for human review. This skill never writes to `.claude/rules/`.
- Thinking "update-capture returned empty proposals, I should re-run it with better context"? Stop. Empty proposals is a valid outcome — not every change produces knowledge. Display the result and return.
- Thinking "I should also run the build check or review chain to verify the change"? Stop. Update Truth runs post-merge. Verification happened in Process Change.
- Thinking "I should read the scan results to give better proposals"? Stop. The agent reads its own inputs. This skill reads the agent's output only.

## Boundary Constraints

- Dispatch only: update-capture.
- Do not analyze code, diffs, or pipeline results itself.
- Do not write to `.claude/rules/`, `docs/decisions.md`, `docs/system-map.md`, or any knowledge substrate file.
- Do not modify any `.pipeline/` file other than the `rm -f` in Step 1.
- Do not launch the Explore agent.
- Do not dispatch agents directly other than update-capture.
- Do not scan the codebase. No `Grep`/`Glob`.
- No retry budget. If update-capture fails, report and return.
