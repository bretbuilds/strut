# run-implementation Examples

## Happy path: no retries needed

```
Step 3: git-tool (branch) → status: "created", branch: feature/add-response-action
Step 4: impl-write-tests → status: "passed", 3 tests written, all failing
Step 5: impl-write-code → status: "passed", 2 files modified
Step 6: run-review-chain → status: "passed"
Step 8: git-tool (commit) → status: "committed", sha: abcd1234
```

Result: `implementation-status.json` with `status: "passed"`, `completed_tasks: ["task-1"]`, `retries_used: 0`, `stages_run: ["branch", "tests", "code", "review-chain", "commit"]`.

## Review chain failure with retry: review fails once, passes on retry

```
Step 3: git-tool (branch) → status: "created"
Step 4: impl-write-tests → status: "passed"
Step 5: impl-write-code → status: "passed"
Step 6: run-review-chain → status: "failed"
```

review-chain-result.json contains:

```json
{
  "skill": "run-review-chain",
  "status": "failed",
  "task_id": "task-1",
  "reviewers_run": ["review-scope"],
  "failed_at": "review-scope",
  "scope_issues": [
    {
      "type": "unexpected_file",
      "path": "app/lib/analytics.ts",
      "issue": "File modified but not listed in implementation_notes.files_to_modify or tests-result.test_files."
    }
  ],
  "criteria_issues": [],
  "criteria_verdicts": [],
  "summary": "Review chain failed at review-scope. 1 scope issue(s)."
}
```

Orchestrator: `retries_used` is 0, under budget of 3. Increment to 1. Re-dispatch impl-write-code.

```
Step 5 (retry): impl-write-code reads review-chain-result.json as feedback → status: "passed"
Step 6 (retry): run-review-chain → status: "passed"
Step 8: git-tool (commit) → status: "committed"
```

Result: `implementation-status.json` with `status: "passed"`, `completed_tasks: ["task-1"]`, `retries_used: 1`, `stages_run: ["branch", "tests", "code", "review-chain", "code", "review-chain", "commit"]`.

## Key behavior: what impl-write-code sees on retry

On retry after review chain failure, impl-write-code's input contract adds one file:

| File | What impl-write-code does with it |
|------|-----------------------------------|
| `review-chain-result.json` | Reads `scope_issues[]` and `criteria_issues[]`. Revises only what the reviewers flagged. Preserves everything the reviewers did not flag. |

impl-write-code does NOT rewrite from scratch — it reads its own prior modifications and applies targeted fixes per the review feedback.

## Budget exhaustion: 3 retries, review still failing

```
Step 5: impl-write-code → passed
Step 6: run-review-chain → failed (retry 1)
Step 5: impl-write-code → passed
Step 6: run-review-chain → failed (retry 2)
Step 5: impl-write-code → passed
Step 6: run-review-chain → failed (retry 3)
```

Orchestrator: `retries_used == 3`, budget exhausted. Writes:

```json
{
  "skill": "run-implementation",
  "status": "failed",
  "completed_tasks": [],
  "failed_task": "task-1",
  "retries_used": 3,
  "stages_run": ["branch", "tests", "code", "review-chain", "code", "review-chain", "code", "review-chain"],
  "failed_at": "review-chain",
  "summary": "Review chain retry budget exhausted (3 retries). Latest failure at review-chain. See review-chain-result.json."
}
```

run-process-change reads `status: "failed"` and writes `process-change-state.json` with `failed_at: "implementation"`.

## Decompose ON: multi-task iteration (3 tasks, retry on task 2)

Step 2b reads `classification.json.modifiers.decompose = true` and `spec.json.tasks[]` with 3 tasks.

**First invocation** — task 1 only (until task_1 gate):

```
Step 3: git-tool (branch) → status: "created", branch: feature/add-multi-layer-feature

--- Task task-1 ---
Write active-task.json: {"task_id": "task-1"}
Step 4: impl-write-tests → status: "passed", 2 tests written
Step 5: impl-write-code → status: "passed"
Step 6: run-review-chain → status: "passed"
Step 8: git-tool (commit) → status: "committed", sha: aaa111
Step 8b: completed_tasks has 1 entry and 2 tasks remain → BLOCKED
```

Result (first invocation):

```json
{
  "skill": "run-implementation",
  "status": "blocked",
  "gate": "task_1",
  "completed_tasks": ["task-1"],
  "remaining_tasks": ["task-2", "task-3"],
  "branch_name": "feature/add-multi-layer-feature",
  "per_task": [
    {"task_id": "task-1", "commit_sha": "aaa111", "retries_used": 0}
  ],
  "stages_run": ["branch", "task-1:tests", "task-1:code", "task-1:review-chain", "task-1:commit"],
  "summary": "Task task-1 committed. Pausing for task-1 gate validation before proceeding to task-2."
}
```

run-process-change writes task_1 gate state, pauses. Human reviews task-1 diff and responds `continue`.

**Second invocation** — dispatched with `args: "task-2"`. Step 2b reads the blocked implementation-status.json to recover `per_task` and `stages_run` from the first invocation:

```
--- Task task-2 ---
Write active-task.json: {"task_id": "task-2"}
Step 4: impl-write-tests → status: "passed", 2 tests written
Step 5: impl-write-code → status: "passed"
Step 6: run-review-chain → status: "failed" (retry 1)
Step 5: impl-write-code → status: "passed"
Step 6: run-review-chain → status: "passed"
Step 8: git-tool (commit) → status: "committed", sha: bbb222
[context compaction]

--- Task task-3 ---
Write active-task.json: {"task_id": "task-3"}
Step 4: impl-write-tests → status: "passed", 1 test written
Step 5: impl-write-code → status: "passed"
Step 6: run-review-chain → status: "passed"
Step 8: git-tool (commit) → status: "committed", sha: ccc333
```

Result (second invocation — final):

```json
{
  "skill": "run-implementation",
  "status": "passed",
  "completed_tasks": ["task-1", "task-2", "task-3"],
  "branch_name": "feature/add-multi-layer-feature",
  "per_task": [
    {"task_id": "task-1", "commit_sha": "aaa111", "retries_used": 0},
    {"task_id": "task-2", "commit_sha": "bbb222", "retries_used": 1},
    {"task_id": "task-3", "commit_sha": "ccc333", "retries_used": 0}
  ],
  "stages_run": ["branch", "task-1:tests", "task-1:code", "task-1:review-chain", "task-1:commit", "task-2:tests", "task-2:code", "task-2:review-chain", "task-2:code", "task-2:review-chain", "task-2:commit", "task-3:tests", "task-3:code", "task-3:review-chain", "task-3:commit"],
  "summary": "Implementation cycle complete. 3 tasks committed on feature/add-multi-layer-feature."
}
```

Key behaviors: task_1 gate pauses after task 1 for human validation. On resume, run-implementation receives `args: "task-2"` and starts from there — Step 2b recovers `per_task` and `stages_run` from the blocked status file. Retry budget resets per task (task-2 used 1 retry; task-3 started fresh at 0). Context compaction happens between tasks. `active-task.json` is overwritten before each task's cycle. Each task gets its own commit.

## Decompose ON: failure mid-loop (task 2 exhausts retries)

```
--- Task task-1 ---
[completes normally]

--- Task task-2 ---
Step 5: impl-write-code → passed
Step 6: run-review-chain → failed (retry 1)
Step 5: impl-write-code → passed
Step 6: run-review-chain → failed (retry 2)
Step 5: impl-write-code → passed
Step 6: run-review-chain → failed (retry 3)
```

Result:

```json
{
  "skill": "run-implementation",
  "status": "failed",
  "completed_tasks": ["task-1"],
  "failed_task": "task-2",
  "failed_at": "review-chain",
  "branch_name": "feature/add-multi-layer-feature",
  "retries_used": 3,
  "stages_run": ["branch", "task-1:tests", "task-1:code", "task-1:review-chain", "task-1:commit", "task-2:tests", "task-2:code", "task-2:review-chain", "task-2:code", "task-2:review-chain", "task-2:code", "task-2:review-chain"],
  "summary": "Review chain retry budget exhausted (3 retries) on task task-2. See task-2/review-chain-result.json."
}
```

Task 1's commit survives on the branch. run-process-change reads `status: "failed"` and escalates to the human.

## What survives retries vs what gets re-dispatched

| Component | On review retry | On fresh dispatch |
|-----------|----------------|-------------------|
| git-branch-result.json | Survives | Survives (branch already exists) |
| tests-result.json | Survives | Re-written |
| impl-write-code-result.json | Re-written | Re-written |
| review-chain-result.json | Re-written (by run-review-chain) | Re-written |
| review-scope.json | Re-written (by run-review-chain Step 1 cleanup) | Re-written |
| review-criteria-eval.json | Re-written (by run-review-chain Step 1 cleanup) | Re-written |
| git-commit-result.json | Not yet written | Re-written |

Tests survive review retries because the review chain evaluates the implementation against the tests — the tests themselves don't change.
