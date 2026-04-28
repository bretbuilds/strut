---
name: run-build-check
description: Sub-orchestrator for build verification. Runs the build-check script, dispatches build-error-cleanup on failure, and loops up to 3 cleanup cycles. Writes an aggregated build-result.json. Runs in Process Change, dispatched by run-process-change.
---

# run-build-check

Process Change phase, Build Verification. Dispatched by run-process-change.

Run `.claude/scripts/build-check.sh`, and if it reports failure, dispatch the build-error-cleanup agent and re-run the script. Loop up to 3 cleanup attempts. Aggregate the outcome into `.pipeline/build-check/build-result.json` and return to run-process-change. Retry budget is 3 cleanups; no sub-retry at finer granularity. Do not evaluate build output — route on `status` only.

## Dispatches

- `.claude/scripts/build-check.sh` (bash script, via Bash) — runs 1–4 times per invocation (1 initial + up to 3 post-cleanup re-runs).
- build-error-cleanup (agent) — dispatched only when the preceding `build-check.sh` reported `status: "failed"`. Runs at most 3 times.

## Input Contract

### Files Read (for status routing only)

- `.pipeline/build-check/build-check.json` — read after every `build-check.sh` run. Only the top-level `status` field is routed on.
- `.pipeline/build-check/build-error-cleanup.json` — read after every cleanup dispatch. Only the top-level `status` field is routed on.

### Other Inputs

- None. No `$ARGUMENTS`. The skill reads no prerequisite files beyond what it writes itself — `build-check.sh` is self-contained (detects its own toolchain or reads `.strut/build.json`).

### Prerequisite Files

None. The build-check script runs against the current working tree regardless of what preceded it.

## Output Contract

### Result File

- `.pipeline/build-check/build-result.json`

Written directly.

### Result Schema

Passed:

```json
{
  "skill": "run-build-check",
  "status": "passed",
  "attempts": 1,
  "cleanups_run": 0,
  "summary": "Build verification passed on initial run."
}
```

Failed:

```json
{
  "skill": "run-build-check",
  "status": "failed",
  "attempts": 4,
  "cleanups_run": 3,
  "failed_reason": "retry_budget_exhausted",
  "summary": "Build verification failed after 3 cleanup attempts. See .pipeline/build-check/build-check.json for the remaining errors."
}
```

- `attempts` — number of times `build-check.sh` ran this invocation (1 to 4).
- `cleanups_run` — number of times build-error-cleanup was dispatched, regardless of outcome (0 to 3). A cleanup that returned `failed` still counts.
- `failed_reason` — present only on `failed`. One of: `build_check_output_missing`, `build_check_output_malformed`, `cleanup_output_missing`, `cleanup_declined`, `retry_budget_exhausted`.

### Status Values

- `passed` — `build-check.sh` returned `status: "passed"` on the initial run or on any post-cleanup re-run within the budget.
- `failed` — one of: the initial or a subsequent `build-check.sh` run produced no parseable `build-check.json`; a cleanup dispatch produced no `build-error-cleanup.json`; cleanup returned `status: "failed"` (declined to attempt a fix); budget exhausted (3 cleanups ran and `build-check.sh` still reports failure).

No other status values.

### Return to run-process-change

On success or failure, run-process-change reads `build-result.json` and routes on `status`. On failure, the pipeline halts — run-process-change does not have a build-check retry layer of its own.

## Dispatch Sequence

### Step 1: Setup

```bash
mkdir -p .pipeline/build-check
rm -f .pipeline/build-check/build-check.json
rm -f .pipeline/build-check/build-error-cleanup.json
rm -f .pipeline/build-check/build-result.json
```

Stale files from a previous invocation must be removed — reading them as fresh output would route incorrectly.

Initialize orchestrator-local counters: `attempts = 0`, `cleanups_run = 0`.

### Step 2: Initial build-check run

Run `bash .claude/scripts/build-check.sh` via the Bash tool. Increment `attempts` to 1.

When the script completes, check: does `.pipeline/build-check/build-check.json` exist and parse as JSON?

- **No (missing or malformed):** go to Step 6 with `failed_reason = "build_check_output_missing"` or `"build_check_output_malformed"`, overwrite placeholder, stop.
- **Yes:** read ONLY the top-level `status` field.
  - `"passed"` →
    **Step pause.** If `.pipeline/step-mode` exists, say `STEP: build-check — passed (initial run). Output: .pipeline/build-check/build-check.json. Next: write passed result.` Ask `Continue? (yes / abort)` and wait. If `abort`, say `Pipeline stopped at step pause.` and stop.
    Go to Step 5 (overwrite placeholder with passed result, stop).
  - `"failed"` → continue to Step 3.
  - any other value → treat as malformed, go to Step 6 with `failed_reason = "build_check_output_malformed"`.

### Step 3: Cleanup loop — up to 3 iterations

Enter a loop. Each iteration must run these sub-steps in order:

#### Step 3a: Budget check

If `cleanups_run == 3`, exit the loop and go to Step 6 with `failed_reason = "retry_budget_exhausted"`.

#### Step 3b: Dispatch build-error-cleanup

Increment `cleanups_run` before dispatching.

Dispatch the build-error-cleanup agent via the Agent tool with `subagent_type: "build-error-cleanup"`. The prompt is `run`.

When the agent completes, check: does `.pipeline/build-check/build-error-cleanup.json` exist and parse as JSON?

- **No (missing or malformed):** go to Step 6 with `failed_reason = "cleanup_output_missing"`, overwrite placeholder, stop.
- **Yes:** read ONLY the top-level `status` field.
  - `"fixed"` →
    **Step pause.** If `.pipeline/step-mode` exists, say `STEP: build-error-cleanup — fixed (attempt [cleanups_run]). Output: .pipeline/build-check/build-error-cleanup.json. Next: re-run build-check.` Ask `Continue? (yes / abort)` and wait. If `abort`, say `Pipeline stopped at step pause.` and stop.
    Continue to Step 3c.
  - `"failed"` → go to Step 6 with `failed_reason = "cleanup_declined"`, overwrite placeholder, stop.
  - any other value → treat as malformed, go to Step 6 with `failed_reason = "cleanup_output_missing"`.

#### Step 3c: Re-run build-check

Run `bash .claude/scripts/build-check.sh` via the Bash tool. Increment `attempts`.

When the script completes, check: does `.pipeline/build-check/build-check.json` exist and parse as JSON?

- **No (missing or malformed):** go to Step 6 with `failed_reason = "build_check_output_missing"` or `"build_check_output_malformed"`.
- **Yes:** read ONLY the top-level `status` field.
  - `"passed"` → go to Step 5.
  - `"failed"` → continue the loop (return to Step 3a).
  - any other value → treat as malformed, go to Step 6.

### Step 5: Overwrite placeholder with passed result

Overwrite `.pipeline/build-check/build-result.json` with:

```json
{
  "skill": "run-build-check",
  "status": "passed",
  "attempts": <final attempts value>,
  "cleanups_run": <final cleanups_run value>,
  "summary": "Build verification passed<on initial run | after N cleanup attempt(s)>."
}
```

Say `Build verification passed.` Return to run-process-change.

### Step 6: Overwrite placeholder with failed result

Overwrite `.pipeline/build-check/build-result.json` with:

```json
{
  "skill": "run-build-check",
  "status": "failed",
  "attempts": <final attempts value>,
  "cleanups_run": <final cleanups_run value>,
  "failed_reason": "<one of: build_check_output_missing | build_check_output_malformed | cleanup_output_missing | cleanup_declined | retry_budget_exhausted>",
  "summary": "<one-line description naming the specific failure. Reference .pipeline/build-check/build-check.json or .pipeline/build-check/build-error-cleanup.json for details.>"
}
```

Say `Build verification failed at [failed_reason]. See build-result.json.` Return to run-process-change.

## Anti-Rationalization Rules

- Thinking "the build-check script failed but the errors look trivial, I'll fix them myself instead of dispatching cleanup"? Stop. This skill dispatches. It does not reason about code or edit files. Dispatch build-error-cleanup every time `build-check.sh` reports failure (until budget exhausted).
- Thinking "I'll read the error output from build-check.json to write a richer summary"? Stop. You route on `status` only. The orchestrator reads structured fields; humans read the referenced files. You do not interpret tool output.
- Thinking "the cleanup agent reported fixed but I'm skeptical, I'll run some spot checks"? Stop. You re-run `build-check.sh` — that IS the spot check. The script is the ground truth.
- Thinking "cleanup returned failed on the first try, let me dispatch it again with more context"? Stop. `failed` from cleanup means the agent could not attempt a fix within its constraints. Re-dispatching will not change that. Write `cleanup_declined`, stop.
- Thinking "I've used 2 cleanups and the errors are close to fixed, one more cycle and we're there — let me allow 4"? Stop. Budget is 3. When `cleanups_run == 3`, exit. Escalating to the human at the budget boundary is the design.
- Thinking "I'll cache build-check.json's passing result so I don't have to re-run the script on resume"? Stop. This skill always runs the script fresh. Resume logic lives one level up in run-process-change.
- Thinking "cleanup produced no output file, maybe there was a permission error, I'll retry it once"? Stop. One dispatch, one read. If the file is missing, the agent failed to comply. Write `cleanup_output_missing`, stop. run-process-change does not have a build-check retry layer — escalation lands at the human.
- Thinking "I should add a cooldown or sanity check between cleanup and re-run"? Stop. The loop is cleanup → re-run → cleanup → re-run. No intermediate steps.
- Thinking "I should read the cleanup's `files_modified` to report which files were edited"? Stop. Route on status. Human debugging reads the files directly.
- Thinking "a prerequisite state is missing (no spec.json or no branch), I'll bail early"? Stop. This skill has no prerequisites — `build-check.sh` is self-contained. Run it regardless. If the project has no toolchain, the script reports detection failure and this skill writes `failed` normally.

## Boundary Constraints

- Dispatch only: `bash .claude/scripts/build-check.sh` (via Bash) and build-error-cleanup (via Task).
- Do not interpret build/lint/type/test errors itself.
- Do not edit source, test, or config files.
- Do not modify `build-check.json` or `build-error-cleanup.json` — those are owned by the script and the agent respectively.
- Do not retry the script, the cleanup agent, or any downstream step individually. The loop IS the retry structure.
- Do not scan the codebase. No `Grep`/`Glob`.
- Do not commit. Edits from cleanup ride along with the task commit made earlier by run-implementation.
- Do not dispatch impl-write-code, impl-write-tests, or any review chain agent.
- Do not launch the Explore agent.
