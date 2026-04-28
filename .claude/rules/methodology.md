# Methodology Rules

## Classification

1. Classification is determined by the pipeline, not by session-level Claude. run-read-truth dispatches truth-repo-impact-scan and truth-classify, which write `classification.json`. Session Claude displays the result to the human before proceeding — it does not produce, interpret, or adjust the classification.
2. Trust modifier triggers: the six `risk_signals` booleans — `auth`, `rls`, `schema`, `security`, `immutability`, `multi_tenant`. These are hard triggers — if ANY signal is true, trust is ON regardless of perceived simplicity.
3. Decompose modifier triggers: change crosses 2+ architectural boundaries (UI / server / database) per `boundary_crossings` from the scan. Decompose ON means task breakdown (≤5 tasks), per-task TDD loop, and task 1 human gate.
4. Trust and decompose are independent. They can stack (guarded-decompose = both ON). Stacking always increases ceremony, never decreases it.
5. The human can override modifiers upward or proceed as classified. Overriding modifiers downward is the human's prerogative at the gate — session Claude never suggests it.

## TDD Enforcement

6. Pipelined changes: tests MUST exist and fail before implementation code is written. impl-write-tests runs before impl-write-code — this is structural, not optional.
7. Thinking about writing implementation code before a failing test exists? Stop. Delete the implementation. Write the test. Watch it fail. Then implement.
8. Each MUST NEVER entry (trust ON) becomes a negative test — the test verifies the violation is rejected, not silently ignored.
9. Write minimum code to pass tests. No anticipatory abstractions.

## Review Chain

10. Review chain runs on every pipelined change: review-scope → review-criteria-eval. Trust ON adds review-security (Opus) as the third step.
11. Fail-fast: if any reviewer fails, stop. impl-write-code re-runs with the failure feedback to produce a revised diff. The full review chain then re-runs from review-scope — the revised implementation may have introduced new issues at any review stage.
12. Shared retry counter: max 3 total retries across the entire chain. Then escalate to human.

## Spec Cycle

13. Spec refinement: spec-derive-intent → spec-write → spec-review. If spec-review fails, spec-write re-runs with feedback. Max 5 iterations.
14. Nothing enters implementation without spec.json existing and a human approving it at the spec approval gate.

## Anti-Rationalization

15. Do NOT launch the Explore agent between pipeline steps or for any reason during execution.
16. Do NOT suggest that modifiers should be lowered, that a change is simpler than the scan determined, or that ceremony can be reduced. The scan's classification stands unless the human overrides it.
17. Do NOT skip review stages, even if the change "looks simple."
18. Do NOT present bypass options when blocked. Write status and wait. Never suggest bypassing the methodology, reducing ceremony, or "temporarily" skipping the pipeline. The human can choose to override — but you do not offer it.

Pipeline internals (skill/agent behavior, file contracts, resume logic) are scoped in `pipeline.md`.
Full architecture: `docs/strut-architecture/core-path-architecture.md`