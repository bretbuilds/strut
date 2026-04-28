# Operating Rules

## Build Requirements

1. Build, lint, type-check, and test must all pass with zero errors before any PR or commit.
2. Enable the strictest type-checking the language supports. Type-system escapes (e.g., `@ts-ignore`, `# type: ignore`, `any` casts) require a comment explaining why.
3. After completing any implementation task, run build + lint + type-check + test. Fix all failures before continuing. Do not mark a task complete until all pass.

## CI/CD

4. Feature branches → PR → CI passes → merge in browser → pull latest `main` locally.
5. Never push directly to `main`/`master`.
6. PR descriptions include: what changed, why, and any MUST NEVER constraints verified. Trust ON changes include the impl-describe-flow output.

## Testing

7. New tests required for all pipelined changes.
8. Tests must be deterministic. Flaky tests are bugs — fix immediately and capture the fix as a rule if the cause is systemic. This is the self-improving rules cycle.

<!-- TODO: Test speed strategy when suite >15s -->

## Scope Discipline

9. Keep changes scoped to 5 or fewer files per task. If more files need changing, propose a plan first.
10. Do not add features, refactor code, or make improvements beyond what was asked. A bug fix does not need surrounding code cleaned up. A feature does not need extra configurability.
11. Do not create helpers, utilities, or abstractions for one-time operations. Three similar lines is better than a premature abstraction. Do not design for hypothetical future requirements.

## Code Generation

12. Prefer intermediate variables over chained operations. One transformation per line.
13. Do not add error handling beyond what the feature requires.
14. Do not write tests beyond what the spec or task requires. No speculative test coverage.
15. Run bash commands individually, not chained with `&&`. Compound commands trigger permission prompts and are harder to debug when one step fails.

<!-- A7: Language-specific code conventions -->

## When Things Go Wrong

16. If an approach fails, diagnose WHY before retrying. Read the error, check assumptions, try a focused fix. Do not retry the identical action. Do not abandon a viable approach after a single failure.
17. If the build fails twice on the same error, or you find yourself undoing a change you just made: STOP and re-plan. Do not attempt a third fix without explaining what went wrong and proposing a different approach.
18. When the same mistake happens twice, or a mistake would affect architecture or data integrity: add a rule to the relevant rules file to prevent it in future sessions. This is knowledge capture — the self-improving rules cycle.

## Environment

<!-- TODO: Project-specific environment rules -->

19. Never test against production data or production services.

## Conventions

<!-- TODO: Project conventions -->
