# Security Rules

## RLS (Row-Level Security)

1. Every table MUST have RLS enabled. No exceptions.
2. Every table's RLS policy MUST independently enforce `org_id`/tenant scoping. A common bypass pattern pivots through a joined table lacking its own tenant check — RLS on the primary table does not protect against this. Verify tenant scoping on EVERY table in the join path.
3. Never use the service role (or equivalent privileged credential) in application code. It is for migrations and admin scripts only.
4. Never disable RLS on a table (e.g., `ALTER TABLE ... DISABLE ROW LEVEL SECURITY` in Postgres).
5. Every RLS policy gets a test that verifies it blocks cross-tenant access.

## Authentication

6. API routes must validate authentication before processing any request.
7. Sensitive data must never be fetched then filtered client-side. If a user should not see it, the query must not fetch it.

## Data Immutability

8. Records marked immutable must reject mutation attempts — not silently ignore them, but actively reject with an error.
9. Immutability rules get tests that verify mutation is rejected.

## Encryption and Secrets

10. No secrets in source code. Use environment variables.
11. API keys use server-side environment variables, never exposed to client.
12. No hardcoded credentials or test data in committed code.

## MUST NEVER Constraints

<!-- B5: Format: "MUST NEVER: [constraint] — added [date] from [source]" -->
