# Example: standard-decompose — New section type with database helper function

## Change request

Add a "Key Contacts" section type with contact search backed by a SQL helper function.

## Scan result (abbreviated)

```json
{
  "skill": "truth-repo-impact-scan",
  "status": "passed",
  "what": "Add a \"Key Contacts\" section type with contact search backed by a SQL helper function",
  "files_to_modify": [
    {
      "path": "app/lib/sections/key-contacts/KeyContactsEditor.tsx",
      "reason": "New file — editor component for the section, includes contact search input",
      "layer": "ui",
      "is_new_file": true
    },
    {
      "path": "app/lib/sections/key-contacts/KeyContactsView.tsx",
      "reason": "New file — recipient view component for the section",
      "layer": "ui",
      "is_new_file": true
    },
    {
      "path": "app/lib/sections/registry.ts",
      "reason": "Section registry — needs new entry for key_contacts type",
      "layer": "server",
      "is_new_file": false
    },
    {
      "path": "app/lib/starter-kits/agency.ts",
      "reason": "Starter kit needs the new section added to its default config",
      "layer": "server",
      "is_new_file": false
    },
    {
      "path": "supabase/sql/search_contacts.sql",
      "reason": "New SQL helper function — full-text contact search scoped by org_id, called via RPC from the editor",
      "layer": "database",
      "is_new_file": true
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
    "layers_touched": ["ui", "server", "database"],
    "boundary_crossings": 2,
    "new_file_count": 3
  },
  "summary": "New section type spanning three layers: two new UI components, two server-layer registry updates, and a new SQL helper function. No trust-sensitive systems touched."
}
```

## Classification result

```json
{
  "skill": "truth-classify",
  "status": "classified",
  "what": "Add a \"Key Contacts\" section type with contact search backed by a SQL helper function",
  "modifiers": {
    "trust": false,
    "decompose": true
  },
  "execution_path": "standard-decompose",
  "what_breaks": "Section fails to render, search returns incorrect results, or registry entry is malformed — worst case is a broken section visible to recipients in a published update",
  "evidence": {
    "risk_signals_true": [],
    "boundary_crossings": 2,
    "layers_touched": ["ui", "server", "database"],
    "trust_rule": "No risk signals → trust OFF",
    "decompose_rule": "boundary_crossings >= 2 → decompose ON"
  }
}
```

## Execution summary

```
CLASSIFICATION COMPLETE
What: Add a "Key Contacts" section type with contact search backed by a SQL helper function
What breaks: Section fails to render, search returns incorrect results, or registry entry is malformed — worst case is a broken section visible to recipients in a published update

Modifiers:
  Trust:     OFF — none
  Decompose: ON — 2 boundary crossings: [ui, server, database]

Execution path: standard-decompose
```

## Why this path

No risk signals fired — the SQL helper function adds new behavior (full-text contact search) without altering any table schema or defining an RLS policy, so schema and rls stay false. The change spans three layers — UI components, server-layer registry entries, and a database-layer SQL function — giving boundary_crossings: 2 and triggering decompose. The result is `standard-decompose`: the work is broken into independently testable tasks (SQL function, registry entry, editor component, view component) with a gate after task 1 to validate the approach before the remaining tasks run.
