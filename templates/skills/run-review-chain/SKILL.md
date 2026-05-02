---
name: run-review-chain
description: Sub-orchestrator for the review sequence. Dispatches review-scope and review-criteria-eval in order with fail-fast routing, then conditionally dispatches review-security when trust is ON. Writes an aggregated review-chain-result.json. Runs in Process Change, dispatched by run-implementation.
---

# run-review-chain

Process Change phase, Review Chain. Dispatched by run-implementation.

Dispatch review-scope first. If it passes, dispatch review-criteria-eval. If trust is ON and review-criteria-eval passes, dispatch review-security. Aggregate the outcome into `.strut-pipeline/implementation/task-1/review-chain-result.json` and return to run-implementation. The parent orchestrator owns the retry budget; this skill has none of its own. Do not evaluate scope, criteria, or security directly.

## Dispatches

- review-scope (agent) — always first
- review-criteria-eval (agent) — only if review-scope passed
- review-security (agent) — only if trust is ON and review-criteria-eval passed

## Input Contract

### Files Read (for status routing and aggregation only)

- `.strut-pipeline/classification.json` — read `modifiers.trust` to determine whether review-security is dispatched.
- `.strut-pipeline/implementation/task-1/review-scope.json` — status check after review-scope; on failure, issues array is copied into `review-chain-result.json`.
- `.strut-pipeline/implementation/task-1/review-criteria-eval.json` — status check after review-criteria-eval; on failure, issues array and per_criterion verdicts are copied into `review-chain-result.json`.
- `.strut-pipeline/implementation/task-1/review-security.json` — status check after review-security (trust ON only); on failure, issues array is copied into `review-chain-result.json`.

For decompose ON, the `task-1` segment is replaced by the active task id passed from run-implementation.

### Other Inputs

- `$ARGUMENTS` (optional): a task id (e.g., `task-2`) for decompose ON. If absent, task id defaults to `task-1`.

### Prerequisite Files

These must exist before this skill runs (produced by run-implementation's earlier steps):

- `.strut-pipeline/spec-refinement/spec.json`
- `.strut-pipeline/classification.json`
- `.strut-pipeline/implementation/<task_id>/tests-result.json` with `status: "passed"`
- `.strut-pipeline/implementation/<task_id>/impl-write-code-result.json` with `status: "passed"`

If any prerequisite is missing, say: `Missing implementation prerequisite: [name]. run-implementation should dispatch impl-write-tests and impl-write-code first.` Stop.

## Output Contract

### Result File

- `.strut-pipeline/implementation/task-1/review-chain-result.json`

Written directly. Aggregated from reviewer outputs.

### Result Schema

Passed (standard path, trust OFF):

```json
{
  "skill": "run-review-chain",
  "status": "passed",
  "task_id": "task-1",
  "trust": false,
  "reviewers_run": ["review-scope", "review-criteria-eval"],
  "scope_issues": [],
  "criteria_issues": [],
  "criteria_verdicts": [],
  "security_issues": [],
  "summary": "Review chain passed. All reviewers approved."
}
```

Passed (trust ON):

```json
{
  "skill": "run-review-chain",
  "status": "passed",
  "task_id": "task-1",
  "trust": true,
  "reviewers_run": ["review-scope", "review-criteria-eval", "review-security"],
  "scope_issues": [],
  "criteria_issues": [],
  "criteria_verdicts": [],
  "security_issues": [],
  "summary": "Review chain passed. All 3 reviewers approved."
}
```

Failed:

```json
{
  "skill": "run-review-chain",
  "status": "failed",
  "task_id": "task-1",
  "trust": true,
  "reviewers_run": ["review-scope", "review-criteria-eval", "review-security"],
  "failed_at": "review-security",
  "scope_issues": [],
  "criteria_issues": [],
  "criteria_verdicts": [],
  "security_issues": [
    {
      "type": "tenant_leak",
      "severity": "critical",
      "path": "app/actions/get-items.ts",
      "lines": "14-22",
      "issue": "Query joins through org_members without tenant scoping on org_members itself.",
      "rule_violated": "strut-security.md rule 2"
    }
  ],
  "summary": "Review chain failed at review-security. 1 security issue(s)."
}
```

`scope_issues[]` is copied verbatim from `review-scope.json.issues[]` when review-scope failed. `criteria_issues[]` and `criteria_verdicts[]` are copied from `review-criteria-eval.json.issues[]` and `review-criteria-eval.json.per_criterion[]` when that reviewer ran. `security_issues[]` is copied from `review-security.json.issues[]` when that reviewer ran (trust ON only).

### Status Values

- `passed` — All dispatched reviewers returned `status: "passed"`. (2 reviewers for standard path, 3 for trust ON.)
- `failed` — Any reviewer failed, or a reviewer did not produce output.

No other status values.

### Return to run-implementation

On success or failure, run-implementation reads `review-chain-result.json` and routes on `status`. On failure, impl-write-code reads the same file as its retry feedback source.

## Dispatch Sequence

### Step 1: Setup

Parse `$ARGUMENTS`. The first token (if present) is the task id; otherwise task id is `task-1`.

```bash
mkdir -p .strut-pipeline/implementation/<task_id>
rm -f .strut-pipeline/implementation/<task_id>/review-scope.json
rm -f .strut-pipeline/implementation/<task_id>/review-criteria-eval.json
rm -f .strut-pipeline/implementation/<task_id>/review-security.json
rm -f .strut-pipeline/implementation/<task_id>/review-chain-result.json
```

Stale reviewer files must be removed — every dispatch starts from review-scope. The revised implementation may have introduced new issues at any stage.

### Step 2: Read classification and verify prerequisites

Read `.strut-pipeline/classification.json`. Extract `modifiers.trust` → `trust_on` (boolean).

Check that `.strut-pipeline/spec-refinement/spec.json`, `.strut-pipeline/implementation/<task_id>/tests-result.json`, and `.strut-pipeline/implementation/<task_id>/impl-write-code-result.json` all exist. If any is missing, overwrite `review-chain-result.json` with `status: "failed"`, `failed_at: "prerequisites"`, and a `summary` naming which prerequisite file is missing. Stop.

Do not check upstream statuses here — the reviewers validate their own inputs per their contracts.

### Step 3: Dispatch review-scope

Dispatch the review-scope agent via the Agent tool with `subagent_type: "review-scope"`. The prompt instructs it to evaluate the current diff against the spec, for the active task id.

When the agent completes, check: does `.strut-pipeline/implementation/<task_id>/review-scope.json` exist?

- **Yes:** Read ONLY the `status` field.
  - If `"passed"`:
    **Step pause.** If `.strut-pipeline/step-mode` exists, say `STEP: review-scope — passed (task <task_id>). Output: .strut-pipeline/implementation/<task_id>/review-scope.json. Next: review-criteria-eval.` Ask `Continue? (yes / abort)` and wait. If `abort`, say `Pipeline stopped at step pause.` and stop.
    Continue to Step 4.
  - If `"failed"`: go to Step 7 (aggregate failure, stop).
- **No:** Go to Step 7 with a synthetic failure (reviewers_run=["review-scope"], failed_at="review-scope", summary names the missing output).

### Step 4: Dispatch review-criteria-eval

Dispatch the review-criteria-eval agent via the Agent tool with `subagent_type: "review-criteria-eval"`. The prompt instructs it to evaluate criteria satisfaction for the active task id.

When the agent completes, check: does `.strut-pipeline/implementation/<task_id>/review-criteria-eval.json` exist?

- **Yes:** Read ONLY the `status` field.
  - If `"passed"`:
    **Step pause.** If `.strut-pipeline/step-mode` exists, say `STEP: review-criteria-eval — passed (task <task_id>). Output: .strut-pipeline/implementation/<task_id>/review-criteria-eval.json. Next: [review-security if trust ON, otherwise write passed result].` Ask `Continue? (yes / abort)` and wait. If `abort`, say `Pipeline stopped at step pause.` and stop.
    If `trust_on` is true: continue to Step 5. If `trust_on` is false: continue to Step 6.
  - If `"failed"`: go to Step 7 (aggregate failure, stop).
- **No:** Go to Step 7 with a synthetic failure (reviewers_run includes both, failed_at="review-criteria-eval", summary names the missing output).

### Step 5: Dispatch review-security (trust ON only)

This step runs only when `trust_on` is true. If `trust_on` is false, this step is skipped entirely.

Dispatch the review-security agent via the Agent tool with `subagent_type: "review-security"`. The prompt instructs it to audit the implementation diff for trust boundary violations for the active task id.

When the agent completes, check: does `.strut-pipeline/implementation/<task_id>/review-security.json` exist?

- **Yes:** Read ONLY the `status` field.
  - If `"passed"`:
    **Step pause.** If `.strut-pipeline/step-mode` exists, say `STEP: review-security — passed (task <task_id>). Output: .strut-pipeline/implementation/<task_id>/review-security.json. Next: write passed result.` Ask `Continue? (yes / abort)` and wait. If `abort`, say `Pipeline stopped at step pause.` and stop.
    Continue to Step 6.
  - If `"failed"`: go to Step 7 (aggregate failure, stop).
- **No:** Go to Step 7 with a synthetic failure (reviewers_run includes all three, failed_at="review-security", summary names the missing output).

### Step 6: Overwrite placeholder with passed result

Overwrite `.strut-pipeline/implementation/<task_id>/review-chain-result.json` with:

If `trust_on` is false:

```json
{
  "skill": "run-review-chain",
  "status": "passed",
  "task_id": "<task_id>",
  "trust": false,
  "reviewers_run": ["review-scope", "review-criteria-eval"],
  "scope_issues": [],
  "criteria_issues": [],
  "criteria_verdicts": [],
  "security_issues": [],
  "summary": "Review chain passed. All reviewers approved."
}
```

If `trust_on` is true:

```json
{
  "skill": "run-review-chain",
  "status": "passed",
  "task_id": "<task_id>",
  "trust": true,
  "reviewers_run": ["review-scope", "review-criteria-eval", "review-security"],
  "scope_issues": [],
  "criteria_issues": [],
  "criteria_verdicts": [],
  "security_issues": [],
  "summary": "Review chain passed. All 3 reviewers approved."
}
```

Say `Review chain complete. All reviewers passed.` Return to run-implementation.

### Step 7: Aggregate failure and overwrite placeholder

Read the failed reviewer's result file (and the previously-passed reviewers', if any) to copy issues and verdicts verbatim.

Overwrite `.strut-pipeline/implementation/<task_id>/review-chain-result.json` with:

```json
{
  "skill": "run-review-chain",
  "status": "failed",
  "task_id": "<task_id>",
  "trust": "<true | false>",
  "reviewers_run": ["<list of reviewers that ran>"],
  "failed_at": "<review-scope | review-criteria-eval | review-security>",
  "scope_issues": [],
  "criteria_issues": [],
  "criteria_verdicts": [],
  "security_issues": [],
  "summary": "Review chain failed at <reviewer>. <counts>."
}
```

Populate `scope_issues[]` from `review-scope.json.issues[]` if review-scope failed or ran. Populate `criteria_issues[]` and `criteria_verdicts[]` from `review-criteria-eval.json.issues[]` and `review-criteria-eval.json.per_criterion[]` if review-criteria-eval ran. Populate `security_issues[]` from `review-security.json.issues[]` if review-security ran (trust ON only).

Say `Review chain failed at [reviewer]. See review-chain-result.json.` Return to run-implementation.

## Examples

Read `examples.md` in this skill's directory for worked aggregation examples: scope-fails (fail-fast), criteria-fails (both ran), and security-fails (trust ON, all three ran).

## Anti-Rationalization Rules

- Thinking "review-scope failed on something minor, I should run review-criteria-eval anyway to collect all feedback at once"? Stop. Fail-fast means stop at the first failed reviewer. impl-write-code fixes scope first; the next review chain dispatch runs review-criteria-eval fresh against the revised code.
- Thinking "review-scope passed last time, I'll skip it on this dispatch to save tokens"? Stop. Every dispatch re-runs from review-scope. The revised implementation may have introduced new scope issues.
- Thinking "I should read the content of the reviewer result files to produce a better summary"? Stop. You copy `issues[]`, `per_criterion[]`, and status verbatim. You do not synthesize or interpret reviewer findings. The downstream impl-write-code reads the structured arrays directly.
- Thinking "the reviewer flagged something questionable, I should override and mark it passed"? Stop. You route on status. The reviewer's judgment stands. If the reviewer is wrong, that is caught at the PR gate.
- Thinking "I should retry a reviewer that failed to produce output"? Stop. No retries at this layer. Aggregate the failure, write the result, return. run-implementation manages retry.
- Thinking "I need to look at the diff myself to verify the reviewer's findings"? Stop. You do not evaluate scope, criteria, or security. That is the reviewers' work.
- Thinking "a prerequisite is missing, I'll just say the error message and exit"? Stop. Write `review-chain-result.json` with the failure before exiting. run-implementation reads the file, not the chat output.
- Thinking "the stale reviewer files from the last run might still be useful — I'll leave them"? Stop. Step 1 `rm -f`s them unconditionally. A stale `review-scope.json` read as fresh output would silently skip the reviewer and corrupt the chain.
- Thinking "trust is ON but the change looks harmless, I'll skip review-security to save Opus tokens"? Stop. Trust ON means review-security runs. The classification stands. You do not evaluate whether the security review is warranted.
- Thinking "review-security failed but the issues look like false positives — I'll pass it"? Stop. You route on status, not on your judgment of the findings. The reviewer's verdict stands.

## Boundary Constraints

- Dispatch only: review-scope, review-criteria-eval, and review-security (trust ON only).
- Do not evaluate scope, criteria satisfaction, security, or test coverage itself.
- Do not read reviewer reasoning fields beyond the structured arrays copied into the aggregated result (`issues[]`, `per_criterion[]`).
- Do not retry reviewers. run-implementation owns the review-chain retry budget (max 3).
- Do not modify any source, test, or spec file.
- Do not scan the codebase. No `Grep`/`Glob`.
- Do not proceed to commit. run-implementation dispatches git-tool (commit mode) after this skill returns passed.
- Do not launch the Explore agent.
