---
name: run-implementation
description: Sub-orchestrator for the TDD cycle. Dispatches git-tool (branch), impl-write-tests, impl-write-code, run-review-chain, and git-tool (commit) in sequence. Manages the impl-write-code → run-review-chain retry loop with a max 3 retry budget. For decompose ON, iterates the TDD cycle per task with context compaction between tasks. Runs in Process Change, dispatched by run-process-change.
---

# run-implementation

Process Change phase, Implementation. Dispatched by run-process-change.

Create the feature branch, then for each task: write failing tests, write the minimum code to pass them, run the review chain, and commit. Loop impl-write-code → run-review-chain on review failure until the chain passes or the retry budget is exhausted. Return to run-process-change with a passed commit or a failure for human escalation. Do not create branches, write tests, write code, review, or commit directly.

For decompose ON (multiple tasks), the TDD cycle (Steps 4–8) iterates once per task. The retry budget resets per task. Between tasks, request context compaction to prevent context accumulation from degrading agent quality. For standard path (single task), the loop executes once — behavior is unchanged.

## Dispatches

- git-tool (agent, mode `branch`) — once, at the start; skipped if branch already exists
- impl-write-tests (agent) — once per task
- impl-write-code (agent) — once per task initially, then on each review chain failure (up to 3 retries per task)
- run-review-chain (sub-orchestrator skill) — once per impl-write-code dispatch
- git-tool (agent, mode `commit`) — once per task, after the review chain passes

## Input Contract

### Files Read (for status routing only)

- `.pipeline/classification.json` — read `modifiers.decompose` in Step 2b to determine task iteration mode.
- `.pipeline/spec-refinement/spec.json` — for decompose ON, read `tasks[]` in Step 2b to get the ordered task list.
- `.pipeline/implementation/git-branch-result.json` — status check after git-tool (branch).
- `.pipeline/implementation/<task_id>/tests-result.json` — status check after impl-write-tests.
- `.pipeline/implementation/<task_id>/impl-write-code-result.json` — status check after impl-write-code.
- `.pipeline/implementation/<task_id>/review-chain-result.json` — status check after run-review-chain; on failure, read as feedback source by the next impl-write-code dispatch per its own input contract.
- `.pipeline/implementation/<task_id>/git-commit-result.json` — status check after git-tool (commit).

For standard path, `<task_id>` is `task-1`. For decompose ON, `<task_id>` is the active task's id from `spec.json.tasks[]`.

### Other Inputs

- `$ARGUMENTS` (optional): for decompose ON resume, a start task id (e.g., `task-2`) to skip already-completed tasks. If absent, iteration starts from the first task. For standard path (decompose OFF), ignored — task id is always `task-1`.

### Prerequisite Files

These must exist before this skill runs (produced by Read Truth and Spec Refinement):

- `.pipeline/classification.json`
- `.pipeline/spec-refinement/spec.json`

If any prerequisite is missing, overwrite the placeholder result file (see Step 1) with `status: "failed"`, `failed_at: "prerequisites"`, and a summary naming which prerequisite is missing. Stop.

## Output Contract

### Result File

- `.pipeline/implementation/implementation-status.json`

Written directly. Aggregated from dispatched agent/skill outputs.

### State File

- `.pipeline/implementation/active-task.json`

Written before each task's dispatch cycle. Agents read this to determine the active task id. Schema:

```json
{
  "task_id": "<current_task_id>"
}
```

### Result Schema

Passed (standard path — single task):

```json
{
  "skill": "run-implementation",
  "status": "passed",
  "completed_tasks": ["task-1"],
  "branch_name": "feature/<slug>",
  "commit_sha": "<sha>",
  "retries_used": 0,
  "stages_run": ["branch", "tests", "code", "review-chain", "commit"],
  "summary": "Implementation cycle complete. Task task-1 committed on feature/<slug>."
}
```

Passed (decompose ON — multiple tasks):

```json
{
  "skill": "run-implementation",
  "status": "passed",
  "completed_tasks": ["task-1", "task-2", "task-3"],
  "branch_name": "feature/<slug>",
  "per_task": [
    {"task_id": "task-1", "commit_sha": "<sha1>", "retries_used": 0},
    {"task_id": "task-2", "commit_sha": "<sha2>", "retries_used": 1},
    {"task_id": "task-3", "commit_sha": "<sha3>", "retries_used": 0}
  ],
  "stages_run": ["branch", "task-1:tests", "task-1:code", "task-1:review-chain", "task-1:commit", "task-2:tests", "..."],
  "summary": "Implementation cycle complete. 3 tasks committed on feature/<slug>."
}
```

Blocked (decompose ON — task-1 gate):

```json
{
  "skill": "run-implementation",
  "status": "blocked",
  "gate": "task_1",
  "completed_tasks": ["task-1"],
  "remaining_tasks": ["task-2", "task-3"],
  "branch_name": "feature/<slug>",
  "per_task": [
    {"task_id": "task-1", "commit_sha": "<sha1>", "retries_used": 0}
  ],
  "stages_run": ["branch", "task-1:tests", "task-1:code", "task-1:review-chain", "task-1:commit"],
  "summary": "Task task-1 committed. Pausing for task-1 gate validation before proceeding to task-2."
}
```

Failed (standard path):

```json
{
  "skill": "run-implementation",
  "status": "failed",
  "completed_tasks": [],
  "failed_task": "task-1",
  "branch_name": "feature/<slug>",
  "retries_used": 3,
  "stages_run": ["branch", "tests", "code", "review-chain", "code", "review-chain", "code", "review-chain"],
  "failed_at": "review-chain",
  "summary": "Review chain retry budget exhausted (3 retries). Latest failure at review-chain. See review-chain-result.json."
}
```

Failed (decompose ON — mid-loop):

```json
{
  "skill": "run-implementation",
  "status": "failed",
  "completed_tasks": ["task-1"],
  "failed_task": "task-2",
  "branch_name": "feature/<slug>",
  "retries_used": 3,
  "stages_run": ["branch", "task-1:tests", "task-1:code", "task-1:review-chain", "task-1:commit", "task-2:tests", "task-2:code", "task-2:review-chain", "task-2:code", "task-2:review-chain", "task-2:code", "task-2:review-chain"],
  "failed_at": "review-chain",
  "summary": "Review chain retry budget exhausted (3 retries) on task task-2. See task-2/review-chain-result.json."
}
```

### Status Values

- `passed` — Branch exists, all tasks completed: tests written and failing, code passed, review chain passed, commit created.
- `blocked` — Task 1 complete, pausing for human validation before remaining tasks. Decompose ON only. run-process-change handles the gate.
- `failed` — Any stage produced `failed` status and could not be retried within budget, or a stage did not produce output.

No other status values.

### Return to run-process-change

On success: run-process-change reads `implementation-status.json` and proceeds to run-build-check.

On failure: run-process-change reads `implementation-status.json` and escalates to the human per its own rules.

## Dispatch Sequence

### Step 1: Setup

Parse `$ARGUMENTS`. For decompose ON: the first token (if present) is a start task id for resume. For standard path: ignored.

```bash
mkdir -p .pipeline/implementation
```

Do not `rm -f .pipeline/implementation/implementation-status.json` — the resume path in Step 2b reads it to recover prior invocation state. Every terminal path (Step 8b, Step 9, and every failure branch) overwrites it, so stale data cannot persist past return.

Do not `rm -f` the per-stage result files here (`tests-result.json`, `impl-write-code-result.json`, `review-chain-result.json`, `git-commit-result.json`). Each dispatched agent or sub-orchestrator owns its own output file and performs its own cleanup.

### Step 2: Verify prerequisites

Check that `.pipeline/classification.json` and `.pipeline/spec-refinement/spec.json` exist. If either is missing, overwrite `implementation-status.json` with `status: "failed"`, `failed_at: "prerequisites"`, and a summary naming which prerequisite is missing. Stop.

### Step 2b: Determine task list

Read `.pipeline/classification.json` field `modifiers.decompose` → `decompose_on` (boolean).

**If `decompose_on` is true:**

Read `.pipeline/spec-refinement/spec.json` field `tasks[]` → `task_list` (ordered array of task objects, each with `id` and `criteria_ids`).

If `task_list` is empty or missing, overwrite `implementation-status.json` with `status: "failed"`, `failed_at: "task_list"`, and a summary stating the spec has no tasks array. Stop.

If `$ARGUMENTS` contains a start task id: find that task in `task_list`. All tasks before it are pre-completed — record their ids in `completed_tasks`. Slice `task_list` to start from the named task. If the start task id is not found in `task_list`, overwrite `implementation-status.json` with `status: "failed"`, `failed_at: "task_list"`, and a summary naming the unrecognized task id. Stop. Read `.pipeline/implementation/implementation-status.json` (the prior invocation's blocked result) to recover `per_task` and `stages_run`. If the file is missing or has no `per_task` field, initialize both fresh.

**If `decompose_on` is false:**

`task_list` contains one entry: the single task from `spec.json.tasks[0]` (standard path always has exactly one task with id `task-1`).

Initialize `completed_tasks = []` (unless pre-populated from start task resume above). Initialize `per_task = []` (unless recovered from prior invocation above). Initialize `stages_run = ["branch"]` (unless recovered from prior invocation above).

### Step 3: Dispatch git-tool (branch)

Dispatch the git-tool agent via the Agent tool with `subagent_type: "git-tool"` and `$ARGUMENTS: "branch"`.

When the agent completes, check: does `.pipeline/implementation/git-branch-result.json` exist?

- **Yes:** Read the `status` field.
  - If `"created"` or `"exists"`: read the `branch_name` field (used in the final result summary).
    **Step pause.** If `.pipeline/step-mode` exists, say `STEP: git-tool (branch) — <status>. Output: .pipeline/implementation/git-branch-result.json. Next: impl-write-tests.` Ask `Continue? (yes / abort)` and wait. If `abort`, say `Pipeline stopped at step pause.` and stop.
    Continue to Step 3b.
  - If `"failed"`: overwrite `implementation-status.json` with `status: "failed"`, `completed_tasks`, `failed_at: "branch"`, and a summary referencing `git-branch-result.json`. Stop.
- **No:** Overwrite `implementation-status.json` with `status: "failed"`, `completed_tasks`, `failed_at: "branch"`, and a summary naming the missing output. Stop.

### Step 3b: Begin per-task loop

Iterate over `task_list` in order. For each task, set `current_task_id` to the task's `id` field. Initialize the per-task retry counter: `retries_used = 0`.

Write `.pipeline/implementation/active-task.json`:

```json
{
  "task_id": "<current_task_id>"
}
```

```bash
mkdir -p .pipeline/implementation/<current_task_id>
```

If `decompose_on` and this is not the first task in the iteration, say `Starting task <current_task_id>.`

Proceed to Step 4 for the current task.

### Step 4: Dispatch impl-write-tests

Dispatch the impl-write-tests agent via the Agent tool with `subagent_type: "impl-write-tests"`. No `$ARGUMENTS` — the agent reads the active task id from `.pipeline/implementation/active-task.json` and the spec from pipeline state.

When the agent completes, check: does `.pipeline/implementation/<current_task_id>/tests-result.json` exist?

- **Yes:** Read ONLY the `status` field.
  - If `"passed"`: append `"tests"` (or `"<current_task_id>:tests"` if `decompose_on`) to `stages_run`.
    **Step pause.** If `.pipeline/step-mode` exists, say `STEP: impl-write-tests — passed (task <current_task_id>). Output: .pipeline/implementation/<current_task_id>/tests-result.json. Next: impl-write-code.` Ask `Continue? (yes / abort)` and wait. If `abort`, say `Pipeline stopped at step pause.` and stop.
    Continue to Step 5.
  - If `"failed"`: overwrite `implementation-status.json` with `status: "failed"`, `completed_tasks`, `failed_task: "<current_task_id>"`, `failed_at: "tests"`, and a summary referencing `tests-result.json`. Stop.
- **No:** Overwrite `implementation-status.json` with `status: "failed"`, `completed_tasks`, `failed_task: "<current_task_id>"`, `failed_at: "tests"`, and a summary naming the missing output. Stop.

### Step 5: Dispatch impl-write-code

Dispatch the impl-write-code agent via the Agent tool with `subagent_type: "impl-write-code"`. No `$ARGUMENTS` — the agent reads the active task id from `.pipeline/implementation/active-task.json`, the spec, the test files, and (on retry) the review chain result from pipeline state.

When the agent completes, check: does `.pipeline/implementation/<current_task_id>/impl-write-code-result.json` exist?

- **Yes:** Read ONLY the `status` field.
  - If `"passed"`: append `"code"` (or `"<current_task_id>:code"` if `decompose_on`) to `stages_run`.
    **Step pause.** If `.pipeline/step-mode` exists, say `STEP: impl-write-code — passed (task <current_task_id>). Output: .pipeline/implementation/<current_task_id>/impl-write-code-result.json. Next: run-review-chain.` Ask `Continue? (yes / abort)` and wait. If `abort`, say `Pipeline stopped at step pause.` and stop.
    Continue to Step 6.
  - If `"failed"`: overwrite `implementation-status.json` with `status: "failed"`, `completed_tasks`, `failed_task: "<current_task_id>"`, `failed_at: "code"`, include `retries_used`, and a summary referencing `impl-write-code-result.json`. Stop.
- **No:** Overwrite `implementation-status.json` with `status: "failed"`, `completed_tasks`, `failed_task: "<current_task_id>"`, `failed_at: "code"`, and a summary naming the missing output. Stop.

### Step 6: Dispatch run-review-chain

Dispatch the run-review-chain sub-orchestrator via the Skill tool with `skill: "run-review-chain"` and `args: "<current_task_id>"`.

When the sub-orchestrator completes, check: does `.pipeline/implementation/<current_task_id>/review-chain-result.json` exist?

- **Yes:** Read ONLY the `status` field.
  - If `"passed"`: append `"review-chain"` (or `"<current_task_id>:review-chain"` if `decompose_on`) to `stages_run`.
    **Step pause.** If `.pipeline/step-mode` exists, say `STEP: run-review-chain — passed (task <current_task_id>). Output: .pipeline/implementation/<current_task_id>/review-chain-result.json. Next: git-tool (commit).` Ask `Continue? (yes / abort)` and wait. If `abort`, say `Pipeline stopped at step pause.` and stop.
    Continue to Step 8.
  - If `"failed"`: append `"review-chain"` (or `"<current_task_id>:review-chain"` if `decompose_on`) to `stages_run`. Continue to Step 7.
- **No:** Overwrite `implementation-status.json` with `status: "failed"`, `completed_tasks`, `failed_task: "<current_task_id>"`, `failed_at: "review-chain"`, include `retries_used`, and a summary naming the missing output. Stop.

### Step 7: Check retry budget

If `retries_used >= 3`: overwrite `implementation-status.json` with `status: "failed"`, `completed_tasks`, `failed_task: "<current_task_id>"`, `failed_at: "review-chain"`, `retries_used: 3`, and a summary naming that the review chain retry budget was exhausted and pointing to `<current_task_id>/review-chain-result.json` for the latest feedback. Stop.

Otherwise: increment `retries_used = retries_used + 1`. Say `Review chain failed for task <current_task_id> (retry [retries_used] of 3). Re-dispatching impl-write-code with feedback.`

**Step pause.** If `.pipeline/step-mode` exists, say `STEP: run-review-chain — failed (task <current_task_id>, retry [retries_used] of 3). Output: .pipeline/implementation/<current_task_id>/review-chain-result.json. Next: impl-write-code (retry).` Ask `Continue? (yes / abort)` and wait. If `abort`, say `Pipeline stopped at step pause.` and stop.

Go to Step 5 (dispatch impl-write-code again). impl-write-code will read `review-chain-result.json` as its feedback source per its own input contract.

### Step 8: Dispatch git-tool (commit)

Dispatch the git-tool agent via the Agent tool with `subagent_type: "git-tool"` and `$ARGUMENTS: "commit <current_task_id>"`.

When the agent completes, check: does `.pipeline/implementation/<current_task_id>/git-commit-result.json` exist?

- **Yes:** Read the `status` field.
  - If `"committed"`: read the `commit_sha` field. Append `"commit"` (or `"<current_task_id>:commit"` if `decompose_on`) to `stages_run`.
    **Step pause.** If `.pipeline/step-mode` exists, say `STEP: git-tool (commit) — committed (task <current_task_id>). Output: .pipeline/implementation/<current_task_id>/git-commit-result.json. Next: per-task completion.` Ask `Continue? (yes / abort)` and wait. If `abort`, say `Pipeline stopped at step pause.` and stop.
    Continue to Step 8b.
  - If `"failed"`: overwrite `implementation-status.json` with `status: "failed"`, `completed_tasks`, `failed_task: "<current_task_id>"`, `failed_at: "commit"`, include `retries_used`, and a summary referencing `git-commit-result.json`. Stop.
- **No:** Overwrite `implementation-status.json` with `status: "failed"`, `completed_tasks`, `failed_task: "<current_task_id>"`, `failed_at: "commit"`, and a summary naming the missing output. Stop.

### Step 8b: Per-task completion

Append `current_task_id` to `completed_tasks`. Append `{"task_id": "<current_task_id>", "commit_sha": "<sha>", "retries_used": <retries_used>}` to `per_task`.

If `decompose_on` and `completed_tasks` has exactly 1 entry (task 1 just finished) and more tasks remain in `task_list`:

  Build `remaining_tasks` = ordered list of remaining task ids from `task_list`.

  Overwrite `.pipeline/implementation/implementation-status.json` with:

  ```json
  {
    "skill": "run-implementation",
    "status": "blocked",
    "gate": "task_1",
    "completed_tasks": ["<completed task id>"],
    "remaining_tasks": ["<next task id>", "..."],
    "branch_name": "<branch_name>",
    "per_task": [<per_task entries so far>],
    "stages_run": [<stages_run so far>],
    "summary": "Task <current_task_id> committed. Pausing for task-1 gate validation before proceeding to <next task id>."
  }
  ```

  Say `Task <current_task_id> committed. Returning to run-process-change for task-1 gate.`
  Stop. Return to run-process-change. Do not proceed to the next task.

If more tasks remain in `task_list` (task 1 gate already passed — this is a resumed dispatch starting from task 2+):
  If `decompose_on`: request context compaction. Say `Task <current_task_id> committed. Compacting context before next task.`
  Return to Step 3b for the next task.

If no more tasks remain:
  Continue to Step 9.

### Step 9: Write passed result

**Standard path** (single task, `decompose_on` is false):

Overwrite `.pipeline/implementation/implementation-status.json` with:

```json
{
  "skill": "run-implementation",
  "status": "passed",
  "completed_tasks": ["task-1"],
  "branch_name": "<branch_name from git-branch-result.json>",
  "commit_sha": "<commit_sha from git-commit-result.json>",
  "retries_used": <retries_used>,
  "stages_run": ["branch", "tests", "code", "review-chain", "commit"],
  "summary": "Implementation cycle complete. Task task-1 committed on <branch_name>."
}
```

If `retries_used > 0`, expand `stages_run` to reflect the repeated `code` and `review-chain` entries (one pair per retry).

**Decompose ON** (multiple tasks):

Overwrite `.pipeline/implementation/implementation-status.json` with:

```json
{
  "skill": "run-implementation",
  "status": "passed",
  "completed_tasks": ["task-1", "task-2", "..."],
  "branch_name": "<branch_name from git-branch-result.json>",
  "per_task": [
    {"task_id": "task-1", "commit_sha": "<sha1>", "retries_used": 0},
    {"task_id": "task-2", "commit_sha": "<sha2>", "retries_used": 1}
  ],
  "stages_run": ["branch", "task-1:tests", "task-1:code", "task-1:review-chain", "task-1:commit", "task-2:tests", "..."],
  "summary": "Implementation cycle complete. N tasks committed on <branch_name>."
}
```

Expand `stages_run` per task: for each task, include the stages that ran (with retry pairs for retries). Prefix each stage with `<task_id>:` to distinguish tasks.

Say `Implementation complete. Returning to run-process-change.` Return.

## Examples

Read `examples.md` in this skill's directory for worked examples: standard path with retries, decompose ON multi-task, budget exhaustion, and what survives retries.

## Anti-Rationalization Rules

- Thinking "impl-write-tests failed because the spec is ambiguous — I should rewrite the spec"? Stop. You do not write or modify specs. A tests failure is an escalation. run-process-change handles it; the human may choose to revise the spec via the PR rejection path.
- Thinking "impl-write-code failed on a lint error — I'll fix it myself so the review chain can run"? Stop. You do not modify source files. Ever. impl-write-code owns the code; a lint-level failure is still a failure. Escalate.
- Thinking "review-scope passed but review-criteria-eval failed — I'll re-dispatch only review-criteria-eval to save tokens"? Stop. run-review-chain decides which reviewers to re-run on its own next dispatch. You re-dispatch run-review-chain as a whole; you do not reach into its internals.
- Thinking "the review chain failed with minor feedback — I should pass it anyway"? Stop. You route on status, not severity. `"failed"` means re-dispatch impl-write-code. Only `"passed"` exits the cycle.
- Thinking "3 retries seems arbitrary — this one is close to passing, one more retry won't hurt"? Stop. The budget is 3 per task. Exceeding it escalates to the human, who can override. You do not override.
- Thinking "the commit failed a pre-commit hook — I'll run the hook manually and retry"? Stop. Hook failure from git-tool is an escalation. You do not modify source files to satisfy hooks; upstream agents produced the code.
- Thinking "I should read impl-write-code's reasoning to check whether the failure is real"? Stop. You route on status. You never read content fields from agent result files beyond the declared routing fields (`status`, `branch_name`, `commit_sha`).
- Thinking "a prerequisite is missing — I'll just say the error message and exit"? Stop. Write `implementation-status.json` with the failure before exiting. run-process-change reads the file, not the chat output.
- Thinking "the branch already exists from a previous run — I should delete it and recreate it to start fresh"? Stop. git-tool (branch) reports `exists` for an existing branch and checks it out. That is the resume path. You do not delete branches; the human owns branch lifecycle.
- Thinking "impl-write-tests passed but the test files look thin — I should re-dispatch it for more coverage"? Stop. Test adequacy is review-criteria-eval's concern. You dispatch each stage exactly once per cycle (except impl-write-code and run-review-chain, which loop on review failure).
- Thinking "task 1 passed but task 2 is similar — I should skip task 2's tests and reuse task 1's"? Stop. Each task gets its own complete TDD cycle. Tests are per-task. Criteria are per-task. No shortcuts across task boundaries.
- Thinking "context is getting long after task 1 — I should skip compaction and push through"? Stop. Request compaction between tasks. Agent quality degrades with accumulated context; compaction is not optional for multi-task iteration.

## Boundary Constraints

- Dispatch only: git-tool (branch mode), impl-write-tests, impl-write-code, run-review-chain, git-tool (commit mode).
- Do not create branches, write tests, write code, review, or commit itself.
- Do not read content fields from agent result files beyond the declared routing fields (`status`, `branch_name`, `commit_sha`).
- Do not retry agents outside the impl-write-code → run-review-chain loop. impl-write-tests runs exactly once per task; a failure escalates. git-tool (branch) runs exactly once; a failure escalates. git-tool (commit) runs exactly once per task; a failure escalates.
- Do not modify any source, test, or spec file.
- Do not scan the codebase. No `Grep`/`Glob`.
- Do not handle the spec approval gate, build check, PR creation, or PR review gate. Those are run-process-change's responsibilities.
- Do not dispatch review-security directly. run-review-chain is the only review orchestrator; trust ON modifies run-review-chain's internal dispatch, not this skill.
- Do not launch the Explore agent.

## Trust ON behavior

Trust ON does not change this skill's dispatch sequence. The review chain's internal composition changes (run-review-chain conditionally dispatches review-security as its third step), but run-implementation still dispatches run-review-chain as a single step and routes on its aggregated status.

## Decompose ON behavior

Decompose ON activates per-task iteration. The orchestrator reads `classification.json.modifiers.decompose` and, when true, reads `spec.json.tasks[]` to build the ordered task list. Steps 4–8 execute once per task (Step 3 runs once for all tasks). The retry budget (3 retries) is per-task — each task starts with a fresh counter.

Between tasks, the orchestrator writes `.pipeline/implementation/active-task.json` with the next task's id and requests context compaction. Agent quality degrades well before the context window fills — do not carry previous task content forward into the next task's dispatch cycle.

The standard path has exactly one task, so the per-task loop executes once with no compaction. Behavior is identical to the pre-loop implementation.

**Task-1 gate:** After task 1's commit (Step 8b), if more tasks remain, the orchestrator writes `implementation-status.json` with `status: "blocked"`, `gate: "task_1"`, `completed_tasks`, and `remaining_tasks`, then stops. run-process-change handles the human gate and re-dispatches for remaining tasks via `$ARGUMENTS` with the start task id. Step 2b's resume logic slices the task list from the start task, recording prior tasks as pre-completed.
