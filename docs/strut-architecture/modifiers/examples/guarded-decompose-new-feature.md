# Example: guarded-decompose — New feature with component, server action, and migration

## Change request

Add a recipient Q&A feature where recipients can submit questions on an update and the sender can respond.

## Scan result (abbreviated)

```json
{
  "skill": "truth-repo-impact-scan",
  "status": "passed",
  "what": "Add a recipient Q&A feature where recipients can submit questions on an update and the sender can respond",
  "files_to_modify": [
    {
      "path": "app/(recipient)/updates/[id]/QuestionForm.tsx",
      "reason": "New file — form for recipient to submit a question",
      "layer": "ui",
      "is_new_file": true
    },
    {
      "path": "app/(owner)/updates/[id]/QuestionThread.tsx",
      "reason": "New file — sender view showing questions and reply input",
      "layer": "ui",
      "is_new_file": true
    },
    {
      "path": "app/lib/actions/submit-question.ts",
      "reason": "New file — server action for recipient question submission, enforces update ownership",
      "layer": "server",
      "is_new_file": true
    },
    {
      "path": "app/lib/actions/answer-question.ts",
      "reason": "New file — server action for sender reply, enforces org_id scoping",
      "layer": "server",
      "is_new_file": true
    },
    {
      "path": "app/lib/queries/questions.ts",
      "reason": "New file — queries for fetching questions by update_id and org_id",
      "layer": "server",
      "is_new_file": true
    },
    {
      "path": "supabase/migrations/20260414_add_questions_table.sql",
      "reason": "New migration — creates questions table with org_id, update_id, author_token, body, answered_at columns",
      "layer": "database",
      "is_new_file": true
    }
  ],
  "risk_signals": {
    "auth": false,
    "rls": false,
    "schema": true,
    "security": false,
    "immutability": false,
    "multi_tenant": true
  },
  "complexity_signals": {
    "layers_touched": ["ui", "server", "database"],
    "boundary_crossings": 2,
    "new_file_count": 6
  },
  "summary": "New feature spanning all three layers: two UI components, three server-layer files, and a schema migration. Two risk signals: schema (new table) and multi_tenant (org_id scoping required on a new data surface)."
}
```

## Classification result

```json
{
  "skill": "truth-classify",
  "status": "classified",
  "what": "Add a recipient Q&A feature where recipients can submit questions on an update and the sender can respond",
  "modifiers": {
    "trust": true,
    "decompose": true
  },
  "execution_path": "guarded-decompose",
  "what_breaks": "A recipient could read or submit questions belonging to a different organization — the questions table has no RLS yet, and cross-tenant access is possible until policies are written and verified",
  "evidence": {
    "risk_signals_true": ["schema", "multi_tenant"],
    "boundary_crossings": 2,
    "layers_touched": ["ui", "server", "database"],
    "trust_rule": "schema, multi_tenant true → trust ON",
    "decompose_rule": "boundary_crossings >= 2 → decompose ON"
  }
}
```

## Execution summary

```
CLASSIFICATION COMPLETE
What: Add a recipient Q&A feature where recipients can submit questions on an update and the sender can respond
What breaks: A recipient could read or submit questions belonging to a different organization — the questions table has no RLS yet, and cross-tenant access is possible until policies are written and verified

Modifiers:
  Trust:     ON — schema, multi_tenant
  Decompose: ON — 2 boundary crossings: [ui, server, database]

Execution path: guarded-decompose
```

## Why this path

Two risk signals fired — schema (new migration creates a table) and multi_tenant (the questions table holds org-scoped data and must be isolated per tenant). Either signal alone is sufficient to set trust ON. The change spans all three layers — UI, server, and database — giving boundary_crossings: 2 and triggering decompose. The result is `guarded-decompose`: the most intensive path. Work is broken into independently testable tasks (migration + RLS, query layer, server actions, UI components) with a security reviewer in the chain, MUST NEVER constraints mandatory in the spec, a gate after task 1, and a deeper architectural review before merge.
