# Classification Cheat Sheet

<!-- `truth-classify` encodes these rules in its agent body; it does not read this file at runtime. -->

Pre-made decisions so classification is deterministic rather than reasoned from first principles. Two modifiers — trust and decompose — determined independently from scan evidence.

## Trust ON (any of these present in scan)

| Trigger | What breaks |
|---------|-------------|
| Touches RLS / access policies | Data leaks across tenants |
| Touches auth or middleware | Auth bypass = full security failure |
| Touches token / session logic | Token scoping, expiry — trust-critical |
| New or modified database table/column | Schema cascades to queries, types, policies |
| Database migration file | Any schema change is high-risk |
| Immutable / protected data (read or write) | Mutations to frozen data break audit integrity |
| Audit records or compliance logic | Trust model depends on correctness |
| Data integrity enforcement code | Breaking constraints breaks trust |
| Service role key usage | Bypasses all access policies |
| Environment variable for secrets/keys | One mistake leaks API keys |
| Cross-tenant data access patterns | Must verify isolation holds |
| Encryption or secret management | Key mishandling = full compromise |

## Trust OFF (none of the above)

Standard review chain. No security reviewer. Criteria-level review.

## Decompose ON (change crosses 2+ architectural boundaries)

| Pattern | Layers | Decompose? |
|---------|--------|------------|
| New component + new server action + migration | UI + server + database | YES (2 crossings) |
| New component + new server action | UI + server | YES (2 crossings, since server action likely implies query layer) |
| New page + new query function | UI + server | Borderline — check if query touches database layer directly |
| New server action + new migration | Server + database | YES (2 crossings with UI if component consumes it) |

The rule is **2+ boundary crossings** between UI, server, and database layers. The scan detects this from the files it identifies.

## Decompose OFF (single layer or adjacent layers)

| Pattern | Layers | Decompose? |
|---------|--------|------------|
| CSS changes across multiple files | UI only | NO |
| Multiple server actions in the same domain | Server only | NO |
| New component + styling | UI only | NO |
| Config file changes | None | NO |
| Single server action + its test | Server only | NO |

## Common changes and expected modifiers

| Change | Trust | Decompose | Path |
|--------|-------|-----------|------|
| Fix a typo / CSS color | OFF | OFF | Consider skipping the pipeline |
| Update a config value | OFF | OFF | Consider skipping the pipeline |
| Add a new section type (registry + editor + view + starter kit) | OFF | ON | standard-decompose |
| Add a loading spinner to a page | OFF | OFF | standard |
| New server action for existing feature | OFF | OFF | standard |
| Add RLS policies to a table | ON | OFF | guarded |
| New feature with component + action + migration | ON | ON | guarded-decompose |
| Modify auth middleware | ON | OFF | guarded |
| Add a new endpoint returning user-scoped data | ON | OFF | guarded |
| Major UI refactor across 8 components | OFF | OFF | standard (single layer) |
| Refactoring with no behavior change + tests pass | OFF | OFF | Consider skipping the pipeline |

## Edge cases

| Scenario | Trust | Decompose | Reasoning |
|----------|-------|-----------|-----------|
| "Just adding a column" | ON | OFF | Schema = trust signal. Single layer = no decompose. |
| New component that mutates data through auth-scoped action | ON | ON | Auth surface = trust. UI + server = decompose. |
| Fixing a bug in a server action | OFF | OFF | Standard. Unless the action touches auth — then trust ON. |
| Fixing a bug in an access policy | ON | OFF | Trust boundary. Single layer. |
| Adding logging or monitoring | OFF | OFF | Consider skipping the pipeline. |
| New endpoint returning public data | OFF | OFF | Standard. New attack surface but no trust signals. |
| New endpoint returning user-scoped data | ON | OFF | Guarded. RLS/auth involved. |
| Adding a new env var for a feature flag | OFF | OFF | Standard. Not secret management. |
| Adding a new env var for an API key | ON | OFF | Guarded. Secret management = trust. |

## When to skip the pipeline

Skipping the pipeline is a decision made before invoking it, not a pipeline output. Consider skipping when ALL of these are true:

- No trust signals
- No new files with logic
- No behavior changes
- Purely cosmetic, config, or copy changes
- Existing test suite covers the affected behavior

When in doubt, run the pipeline. The cost of a standard pass is minutes. The cost of missing a trust-sensitive change is a production incident.