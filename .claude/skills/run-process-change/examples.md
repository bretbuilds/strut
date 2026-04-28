# run-process-change Examples

## Gate response parsing

### Spec approval gate

State: `gate == "spec_approval"`, `next == "implementation"`

| Human says | Match rule | Action |
|---|---|---|
| `continue` | first word `continue` | → Step 6b (Adversarial Spec Attack check; falls through to Step 7 when trust OFF) |
| `approve` | first word `approve` | → Step 6b (same as above) |
| `revise` | first word `revise` | → Step 5 (re-dispatch spec-refinement) |
| `abort` | first word `abort` | Write aborted state, stop |
| `yes` | no match | Say `Unrecognized response.` Stop, no state change |
| `looks good` | no match | Say `Unrecognized response.` Stop, no state change |
| *(empty)* | no match | Say `Unrecognized response.` Stop, no state change |

### Task 1 gate (decompose ON only)

State: `gate == "task_1"`, `next == "implementation_remaining"`

| Human says | Match rule | Action |
|---|---|---|
| `continue` | first word `continue` | → Step 7 (re-dispatch run-implementation with `start_task` as args) |
| `abort` | first word `abort` | Write aborted state, stop |
| `yes` | no match | Say `Unrecognized response.` Stop, no state change |
| *(empty)* | no match | Say `Unrecognized response.` Stop, no state change |

### PR review gate

State: `gate == "pr_review"`, `next == "awaiting_merge"`

| Human says | Match rule | Action |
|---|---|---|
| `merged` | first word `merged` | Write passed state → return to run-strut |
| `reject implementation the error handler swallows exceptions` | first two words `reject implementation` | Rejection routing → Step 7. Feedback = `the error handler swallows exceptions` |
| `reject spec missing the audit log criterion` | first two words `reject spec` | Rejection routing → Step 5. Feedback = `missing the audit log criterion` |
| `abort` | first word `abort` | Write aborted state, stop |
| `reject` | bare `reject`, no target | Say `Unrecognized response.` Stop, no state change |
| `lgtm` | no match | Say `Unrecognized response.` Stop, no state change |
| `ship it` | no match | Say `Unrecognized response.` Stop, no state change |

## Rejection routing — what survives each path

### `reject implementation <feedback>` — code re-runs, tests and branch survive

For each `task-*` directory under `.pipeline/implementation/`:

| Removed (per task dir) | Kept (per task dir) |
|---|---|
| `impl-write-code-result.json` | `tests-result.json` |
| `review-scope.json` | |
| `review-criteria-eval.json` | |
| `review-security.json` | |
| `review-chain-result.json` | |
| `git-commit-result.json` | |

| Removed (top level) | Kept |
|---|---|
| `implementation-status.json` | `git-branch-result.json` |
| `active-task.json` | `.pipeline/spec-refinement/*` |
| `build-result.json`, `impl-describe-flow.txt`, `git-pr-result.json` | |

### `reject spec <feedback>` — spec revises, implementation wiped entirely

| Removed | Kept |
|---|---|
| `.pipeline/implementation/` (entire dir) | `.pipeline/spec-refinement/` (spec-write reads prior spec + feedback) |
| `.pipeline/build-check/` (entire dir) | `.pipeline/classification.json` |
| `.pipeline/git-pr-result.json` | `.pipeline/classification-log.md` |
| `.pipeline/impl-describe-flow.txt` | `.pipeline/impact-scan.md` |
