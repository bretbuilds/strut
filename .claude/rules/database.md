---
globs:
  - db/migrations/**
  - app/queries/**
  - app/actions/**
---

# Database Rules

## Client Usage

1. Server-side code uses the server-side database client.
2. Client-side code uses the browser-side database client. Never import server-only utilities into client code.

## Multi-Tenant Scoping

3. Every table must have `org_id` (or equivalent tenant key) or trace back to one through foreign keys.
4. All queries must include tenant filtering in the query itself. Do not rely on RLS alone — defense in depth.

## Migrations

5. Schema changes always activate the trust modifier (trust ON classification).
6. Migration files are sequential and append-only — never edit an existing migration.
7. Destructive migrations (drop column, drop table) require explicit human approval.
8. Every migration must include both `up` and `down` scripts.

## Query Patterns

9. Use parameterized queries. No string interpolation in SQL.
10. Foreign key columns need indexes.
11. Use foreign key constraints over application-level validation for referential integrity.

## Data Shape Guidelines

12. Use JSONB (or the equivalent semi-structured type) for flexible/configuration data that doesn't need to be queried or joined.
13. Use normalized tables for data that needs to be queried, filtered, or joined.