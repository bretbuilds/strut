# run-review-chain Examples

## Aggregation: review-scope fails (fail-fast, criteria-eval skipped)

review-scope writes `.strut-pipeline/implementation/task-1/review-scope.json`:

```json
{
  "skill": "review-scope",
  "status": "failed",
  "task_id": "task-1",
  "issues": [
    {
      "type": "unexpected_file",
      "path": "app/lib/analytics.ts",
      "issue": "File modified but not listed in implementation_notes.files_to_modify or tests-result.test_files."
    }
  ],
  "summary": "Failed: 1 scope violation(s)."
}
```

review-criteria-eval does NOT run (fail-fast). review-security does NOT run. Aggregate into `review-chain-result.json`:

```json
{
  "skill": "run-review-chain",
  "status": "failed",
  "task_id": "task-1",
  "trust": false,
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
  "security_issues": [],
  "summary": "Review chain failed at review-scope. 1 scope issue(s)."
}
```

`scope_issues[]` copied verbatim from `review-scope.json.issues[]`. `criteria_issues[]`, `criteria_verdicts[]`, and `security_issues[]` empty because those reviewers did not run.

## Aggregation: review-scope passes, review-criteria-eval fails

review-scope returns `status: "passed"` (no issues). review-criteria-eval writes:

```json
{
  "skill": "review-criteria-eval",
  "status": "failed",
  "task_id": "task-1",
  "per_criterion": [
    { "criterion_id": "C1", "verdict": "satisfied" },
    { "criterion_id": "C2", "verdict": "test_does_not_verify_criterion", "detail": "Test asserts return value but criterion requires side-effect verification." }
  ],
  "issues": [
    {
      "type": "weak_test",
      "criterion_id": "C2",
      "detail": "Test asserts return value but criterion requires side-effect verification."
    }
  ],
  "summary": "Failed: 1 weak test."
}
```

Aggregate into `review-chain-result.json`:

```json
{
  "skill": "run-review-chain",
  "status": "failed",
  "task_id": "task-1",
  "trust": false,
  "reviewers_run": ["review-scope", "review-criteria-eval"],
  "failed_at": "review-criteria-eval",
  "scope_issues": [],
  "criteria_issues": [
    {
      "type": "weak_test",
      "criterion_id": "C2",
      "detail": "Test asserts return value but criterion requires side-effect verification."
    }
  ],
  "criteria_verdicts": [
    { "criterion_id": "C1", "verdict": "satisfied" },
    { "criterion_id": "C2", "verdict": "test_does_not_verify_criterion", "detail": "Test asserts return value but criterion requires side-effect verification." }
  ],
  "security_issues": [],
  "summary": "Review chain failed at review-criteria-eval. 1 weak test(s)."
}
```

`scope_issues[]` empty (review-scope passed). `criteria_issues[]` copied from `review-criteria-eval.json.issues[]`. `criteria_verdicts[]` copied from `review-criteria-eval.json.per_criterion[]`. `security_issues[]` empty (review-security did not run — trust OFF or fail-fast before it).

## Aggregation: trust ON, scope and criteria pass, review-security fails

Trust is ON (`classification.json.modifiers.trust` is `true`). review-scope returns `status: "passed"`. review-criteria-eval returns `status: "passed"`. review-security writes:

```json
{
  "skill": "review-security",
  "status": "failed",
  "task_id": "task-1",
  "risk_signals_checked": ["auth", "rls", "multi_tenant"],
  "issues": [
    {
      "type": "tenant_leak",
      "severity": "critical",
      "path": "app/actions/get-items.ts",
      "lines": "14-22",
      "issue": "Query joins through org_members without tenant scoping on org_members itself. RLS on items table does not protect against a pivot through unscoped org_members.",
      "rule_violated": "strut-security.md rule 2"
    }
  ],
  "summary": "Failed: 1 trust boundary violation(s)."
}
```

Aggregate into `review-chain-result.json`:

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
      "issue": "Query joins through org_members without tenant scoping on org_members itself. RLS on items table does not protect against a pivot through unscoped org_members.",
      "rule_violated": "strut-security.md rule 2"
    }
  ],
  "summary": "Review chain failed at review-security. 1 security issue(s)."
}
```

`scope_issues[]` empty (passed). `criteria_issues[]` and `criteria_verdicts[]` empty (passed). `security_issues[]` copied verbatim from `review-security.json.issues[]`.

## Aggregation: trust ON, all three reviewers pass

Trust is ON. All three reviewers return `status: "passed"`. Aggregate into `review-chain-result.json`:

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
