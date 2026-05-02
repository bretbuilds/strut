# run-strut Examples

## Override: human says "trust on"

Given `classification.json` before override:

```json
{
  "status": "classified",
  "what": "Add a spinner to the dashboard",
  "modifiers": { "trust": false, "decompose": false },
  "execution_path": "standard",
  "evidence": {
    "trust_rule": "no risk signals → trust OFF",
    "decompose_rule": "boundary_crossings < 2 → decompose OFF"
  }
}
```

After human says "trust on", update `classification.json` to:

```json
{
  "status": "classified",
  "what": "Add a spinner to the dashboard",
  "modifiers": { "trust": true, "decompose": false },
  "execution_path": "guarded",
  "evidence": {
    "trust_rule": "Human override → trust ON",
    "decompose_rule": "boundary_crossings < 2 → decompose OFF"
  }
}
```

Three fields change: `modifiers.trust` → `true`, `execution_path` recalculated from the matrix (`guarded`), `evidence.trust_rule` updated to note override. All other fields (including `status: "classified"`) stay unchanged.

Append to `.strut-pipeline/classification-log.md`:

```
| 2026-04-14 | Add a spinner to the dashboard | ON | OFF | → guarded | none | 0 (ui) |
```

The `→` prefix on the execution path marks this row as an override.

## Reference: execution path matrix

Source of truth: `.claude/agents/truth-classify.md`

| Trust | Decompose | execution_path |
|---|---|---|
| OFF | OFF | `standard` |
| ON | OFF | `guarded` |
| OFF | ON | `standard-decompose` |
| ON | ON | `guarded-decompose` |
