---
name: run-read-truth
description: Orchestrator for Read Truth. Receives a change request, dispatches truth-repo-impact-scan and truth-classify as agents in sequence. Stops on error. Does no work itself.
---

# run-read-truth

Read Truth phase. Dispatched by run-strut. Shared context with run-strut.

Dispatch truth-repo-impact-scan and truth-classify in sequence so the human receives a deterministic classification grounded in scanned repo evidence. Do not scan, classify, or draft specs.

## Dispatches

- truth-repo-impact-scan (agent)
- truth-classify (agent)

## Input Contract

### Files Read

- `.pipeline/truth-repo-impact-scan-result.json` — status check only (between Step 2 and Step 3)
- `.pipeline/classification.json` — status check only (after Step 3)
- `.pipeline/classification-log.md` — bounded `tail -5` for display only (after Step 3)

### Other Inputs

- The human's change request, passed from run-strut via conversation context. One natural-language sentence.

If no change request is provided, say: `No change request received. run-strut should pass the change request.` Then stop.

## Output Contract

### Result File

None. Outputs are the four files the dispatched agents write:

- `.pipeline/impact-scan.md` (written by truth-repo-impact-scan)
- `.pipeline/truth-repo-impact-scan-result.json` (written by truth-repo-impact-scan)
- `.pipeline/classification.json` (written by truth-classify)
- `.pipeline/classification-log.md` (appended by truth-classify; append-only, never deleted)

### Return to run-strut

On success, return to run-strut with the classification produced by truth-classify already written to `.pipeline/classification.json`. run-strut handles display, override, and phase sequencing.

## Dispatch Sequence

### Step 1: Clean transient pipeline state

```bash
mkdir -p .pipeline
rm -f .pipeline/truth-repo-impact-scan-result.json .pipeline/impact-scan.md .pipeline/classification.json
```

**Do not delete `.pipeline/classification-log.md`.** It is append-only per the architecture. Every classification accumulates there across runs.

### Step 2: Dispatch scan agent

Dispatch the truth-repo-impact-scan agent via the Agent tool with `subagent_type: "truth-repo-impact-scan"`. Pass the human's change request as the `prompt` parameter (the change request text only). The agent's frontmatter declares its model and tools; the dispatch honors them automatically.

When the agent completes, check: does `.pipeline/truth-repo-impact-scan-result.json` exist?

- **Yes:** Read ONLY the `status` field. If `"passed"`, continue to Step 3. If `"blocked"` or `"failed"`, say `Scan returned [status]. Check .pipeline/truth-repo-impact-scan-result.json.` Stop.
- **No:** Say `Scan did not produce output. Re-run /run-strut.` Stop.

Do not proceed to Step 3 unless the file exists AND status is `"passed"`.

**Step pause.** If `.pipeline/step-mode` exists, say `STEP: truth-repo-impact-scan — passed. Output: .pipeline/impact-scan.md. Next: truth-classify.` Ask `Continue? (yes / abort)` and wait. If `abort`, say `Pipeline stopped at step pause.` and stop.

### Step 3: Dispatch classify agent

Dispatch the truth-classify agent via the Agent tool with `subagent_type: "truth-classify"`. The `prompt` parameter should instruct the agent to read `.pipeline/truth-repo-impact-scan-result.json` and classify per its declared rules. The agent's frontmatter declares its model and tools; the dispatch honors them automatically.

When the agent completes, check: does `.pipeline/classification.json` exist?

- **Yes:** Read ONLY the `status` field. If `"classified"`, run `tail -5 .pipeline/classification-log.md` to show the result, say `Read Truth complete.`, and return to run-strut. Otherwise, say `Classification returned [status]. Check .pipeline/classification.json.` Stop.
- **No:** Say `Classification did not produce output. Re-run /run-strut.` Stop.

## Anti-Rationalization Rules

- Thinking "I should read the scan results to give the human more context"? Stop. The classify agent does that.
- Thinking "I should also start the spec to save time"? Stop. Read Truth and Process Change are separate phases.
- Thinking "the scan passed but I want to verify the content looks right"? Stop. You check status, not content. Content is the classify agent's concern.

## Boundary Constraints

- Dispatch only: truth-repo-impact-scan, truth-classify.
- Do not scan the codebase. The scan agent does that.
- Do not classify. The classify agent does that.
- Do not read agent reasoning or content fields — only the `status` field from result files, plus `tail -5` of the classification log for display.
- Do not format or compose summaries. The classification log tail IS the result.
- Do not handle overrides. run-strut handles that.
- Do not proceed to Process Change. run-strut handles phase sequencing.
- Do not launch the Explore agent.
- Do not write specs, tests, or code.
- Do not delete `.pipeline/classification-log.md` — append-only per architecture.
- No retry budget. Read Truth has no retries.
