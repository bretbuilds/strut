# Example: standard — CSS color fix

## Change request

Fix the heading color on the dashboard — should be dark gray not blue.

## Scan result (abbreviated)

```json
{
  "skill": "truth-repo-impact-scan",
  "status": "passed",
  "what": "Fix the heading color on the dashboard — should be dark gray not blue",
  "files_to_modify": [
    {
      "path": "app/(owner)/dashboard/dashboard.css",
      "reason": "Contains the dashboard heading color rule",
      "layer": "ui",
      "is_new_file": false
    }
  ],
  "risk_signals": {
    "auth": false,
    "rls": false,
    "schema": false,
    "security": false,
    "immutability": false,
    "multi_tenant": false
  },
  "complexity_signals": {
    "layers_touched": ["ui"],
    "boundary_crossings": 0,
    "new_file_count": 0
  },
  "summary": "Single CSS file, one color rule. No logic, no data, no trust boundaries."
}
```

## Classification result

```json
{
  "skill": "truth-classify",
  "status": "classified",
  "what": "Fix the heading color on the dashboard — should be dark gray not blue",
  "modifiers": {
    "trust": false,
    "decompose": false
  },
  "execution_path": "standard",
  "what_breaks": "Wrong color is applied — visually incorrect and immediately reversible, no data or trust boundary involved",
  "evidence": {
    "risk_signals_true": [],
    "boundary_crossings": 0,
    "layers_touched": ["ui"],
    "trust_rule": "No risk signals → trust OFF",
    "decompose_rule": "boundary_crossings < 2 → decompose OFF"
  }
}
```

## Execution summary

```
CLASSIFICATION COMPLETE
What: Fix the heading color on the dashboard — should be dark gray not blue
What breaks: Wrong color is applied — visually incorrect and immediately reversible, no data or trust boundary involved

Modifiers:
  Trust:     OFF — none
  Decompose: OFF — 0 boundary crossings: [ui]

Execution path: standard
```

## Why this path

No risk signals fired — the change touches a single CSS file with no auth, RLS, schema, or tenant isolation concerns. With only the UI layer involved, boundary crossings is 0, so both modifiers land OFF and the execution path is `standard`.

Note: a change this small is a good candidate for skipping the pipeline entirely — a direct CSS edit without invoking the pipeline is reasonable. That's an upstream decision (see the cheat sheet's "When to skip the pipeline" section), not a pipeline classification. But if the pipeline is invoked, `standard` is the correct classification — rules are deterministic, and change size does not reduce the path.
