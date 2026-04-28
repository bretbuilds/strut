# Example: guarded — RLS policy on action_responses table

## Change request

Add RLS policies to the action_responses table.

## Scan result (abbreviated)

```json
{
  "skill": "truth-repo-impact-scan",
  "status": "passed",
  "what": "Add RLS policies to the action_responses table",
  "files_to_modify": [
    {
      "path": "supabase/migrations/20260414_add_action_responses_rls.sql",
      "reason": "New migration defining SELECT, INSERT, and UPDATE policies for action_responses",
      "layer": "database",
      "is_new_file": true
    },
    {
      "path": "app/lib/queries/action-responses.ts",
      "reason": "Existing queries may need explicit org_id filtering to pass new policies",
      "layer": "server",
      "is_new_file": false
    },
    {
      "path": "app/lib/actions/respond-to-action.ts",
      "reason": "Server action that inserts responses — must work under the new policies",
      "layer": "server",
      "is_new_file": false
    }
  ],
  "risk_signals": {
    "auth": false,
    "rls": true,
    "schema": true,
    "security": true,
    "immutability": false,
    "multi_tenant": true
  },
  "complexity_signals": {
    "layers_touched": ["server", "database"],
    "boundary_crossings": 1,
    "new_file_count": 1
  },
  "summary": "RLS policy addition with a new migration file, touching two existing server-layer files. Four risk signals: rls, schema, security, multi_tenant."
}
```

## Classification result

```json
{
  "skill": "truth-classify",
  "status": "classified",
  "what": "Add RLS policies to the action_responses table",
  "modifiers": {
    "trust": true,
    "decompose": false
  },
  "execution_path": "guarded",
  "what_breaks": "Any authenticated user can read and write action responses across all organizations — a botched or missing policy leaves cross-tenant data exposed, and a migration cannot be un-run without a rollback migration",
  "evidence": {
    "risk_signals_true": ["rls", "schema", "security", "multi_tenant"],
    "boundary_crossings": 1,
    "layers_touched": ["server", "database"],
    "trust_rule": "rls, schema, security, multi_tenant all true → trust ON",
    "decompose_rule": "boundary_crossings < 2 → decompose OFF"
  }
}
```

## Execution summary

```
CLASSIFICATION COMPLETE
What: Add RLS policies to the action_responses table
What breaks: Any authenticated user can read and write action responses across all organizations — a botched or missing policy leaves cross-tenant data exposed, and a migration cannot be un-run without a rollback migration

Modifiers:
  Trust:     ON — rls, schema, security, multi_tenant
  Decompose: OFF — 1 boundary crossing: [server, database]

Execution path: guarded
```

## Why this path

Four risk signals fired — rls, schema, security, and multi_tenant — any one of which is sufficient to set trust ON. The change touches two layers (server + database), giving boundary_crossings: 1, which is below the threshold of 2 needed for decompose. The result is `guarded`: a single implementation pass with a security reviewer added to the review chain, MUST NEVER constraints mandatory in the spec, and a deeper architectural review. Decompose does not activate because all the work lives in one coherent concern: writing the policy, then verifying the two callers that must satisfy it.
