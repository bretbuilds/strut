# STRUT Model Limitations Log

Known limitations of current LLM behavior that affect pipeline operation. Each entry is grounded in observed testing, not speculation. Entries are removed when a model generation resolves them or an architectural change makes them irrelevant.

Separated from agent files to avoid token cost on every dispatch.

---

## Platform Limitations

### Agent final-message-only visibility

**Affects:** All agents invoked via `--agent`
**Observed in:** truth-classify, truth-repo-impact-scan, spec-write
**Behavior:** Parent process receives only the agent's final assistant message. Intermediate tool calls, tool output, and thinking are invisible to the caller. Directives targeting "first output line" or visible planning steps cannot be observed or verified by the orchestrator.
**Implication:** Do not use observable output as a routing signal. Route on file status only. Behavioral directives about visible output are non-enforceable and waste directive budget.

---

## LLM Limitations

### Reviewer judgment inconsistency across fresh-context dispatches

**Affects:** spec-review (and likely all future reviewer agents)
**Observed in:** Duration-tracking test, iterations 3 vs 4 — identical criterion content flagged as compound in one pass, approved in the other.
**Behavior:** Each dispatch gets fresh isolated context with no memory of prior judgments. The same content can receive different rulings on repeated reads. This is inherent to the isolated-context architecture, which is deliberately chosen to prevent reviewer bias.
**Implication:** Iteration budget absorbs this noise. Not addressable by directive — a "be consistent" instruction has no mechanism when the agent cannot see prior assessments. Passing prior review results as input would stabilize judgments but violate isolation (risk of anchoring bias outweighs consistency benefit).

---

## Addressable Issues (directive candidates if patterns persist)

### spec-write revision drift on unflagged content

**Affects:** spec-write
**Observed in:** Duration-tracking test, pre-preservation-fix (full oscillation) and post-fix (minor regression at iteration 4)
**Behavior:** During revision, spec-write can introduce new defects in criteria it wasn't asked to change. Preservation directive reduced this significantly but did not eliminate it entirely — iteration 4 showed a regression from 2 to 3 issues despite unflagged criteria being preserved byte-identical.
**Current mitigation:** Preservation directive in algorithm step 4 ("only modify what the feedback specifically names"). Iteration budget absorbs residual drift.
**Potential escalation:** If oscillation persists across real-codebase changes, add a verification step requiring spec-write to re-check unchanged criteria against the review phases before submitting. Not yet justified — single observation on an unusually ambiguous change.

### impl-write-code remediation guidance in failure summary

**Affects:** impl-write-code (and likely any worker agent whose failure contract includes a prose `summary`)
**Observed in:** Initial dual-model test, Sonnet transcript, cases B1a, B1b, E1 — agent appended "to unblock, do X" guidance addressed at the orchestrator alongside the factual failure reason.
**Behavior:** The Failure Behavior directive says "Do NOT suggest fixes." The agent complied in structure (no files modified, no retry, exit after write) but slipped remediation advice into the `summary` string. Assertions passed because the status was correct; the drift is in the narrative field only.
**Current mitigation:** None. Single observation; Opus did not exhibit the behavior.
**Potential escalation:** If review of future runs shows the pattern persists, add an anti-rationalization entry explicitly scoped to the `summary` field — e.g., "Thinking 'I should tell the orchestrator how to unblock this'? Stop. The summary names the failure and nothing else." Not yet justified — assertions all pass and the output contract is not violated.

### impl-write-code writes implementation past early-exit on malformed/missing upstream

**Affects:** impl-write-code
**Observed in:** Initial dual-model test, Sonnet transcript, cases B2 (malformed spec) and G2 (phantom test file). Agent created `greet.ts` by inferring from the test file's import path, then wrote `status: failed`. Opus exited earlier in both cases.
**Behavior:** Algorithm steps 2 and 5 instruct the agent to write `failed` and stop when required input is malformed or when declared test files do not exist. Sonnet proceeded past these guards to step 7 (apply plan), wrote inferred implementation code, and only then reported failure. The `failed` status was correct, so no assertion caught it — but the filesystem side effect violates the spirit of the early-exit.
**Current mitigation:** None. Algorithm steps already say "write failed result and stop" at both checkpoints; Sonnet interpreted "stop" loosely enough to still produce code.
**Potential escalation:** If this pattern recurs in integration testing, tighten step 2 and step 5 to explicit "STOP. Do not proceed to step 6. Do not create files." or add an anti-rationalization entry: "Thinking 'I can infer the implementation from the test file path while I'm here'? Stop. Malformed upstream means the orchestrator escalates — not that the agent fills in gaps." Not yet justified — failure contract was honored and the orchestrator routes on status, not on files-written-on-failure.

### git-tool advisory/remediation prose in failure summaries

**Affects:** git-tool (Sonnet), pattern similar to impl-write-code's summary drift
**Observed in:** git-tool round-two test (after placeholder-write hardening), Sonnet transcript, cases B1a and multiple upstream-failure branches. Agent appended "To proceed, the orchestrator needs to dispatch the Read Truth phase first via `run-read-truth`..." and similar "Next steps:" / "Action required:" advisory lines.
**Behavior:** The Failure Behavior section says "Do NOT suggest fixes. Stop and wait." Sonnet complied structurally (result file written, `status: "failed"`, correct summary, no retry) but layered remediation advice onto the conversational output and sometimes into the `summary` field. Not caught by assertions — F2 only checks for specific forbidden strings ("I should also stage", "Explore").
**Current mitigation:** None. Anti-rationalization rules in the agent body already forbid remediation advice; Sonnet inconsistently honors them on genuinely unexpected inputs.
**Potential escalation:** If integration testing shows this leaking into `summary` fields the human reads at gates, tighten F2 to grep for the specific advisory phrases ("To proceed", "Next steps:", "Action required:") or add a scoped anti-rationalization entry. Not yet justified — result-file contract was honored and the orchestrator routes on status, not on narrative prose.

### git-tool conversational drift on unrecognized inputs (Opus)

**Affects:** git-tool (Opus specifically — Sonnet no longer exhibits this after the clarification-preamble anti-rationalization rule landed)
**Observed in:** git-tool round-two test, Opus transcript, F1 (invalid `$ARGUMENTS` value `BADMODE_XYZ`) and G4 (PR mode, trust OFF, no describe-flow). In both, Opus emitted conversational clarification ("What are you trying to do?", "Are you at a pipeline gate where you've approved moving to PR creation?") instead of writing the declared result file and exiting.
**Behavior:** The mode-dispatch algorithm and anti-rationalization rules explicitly forbid clarification requests. Opus overrides them on inputs that look "wildly unexpected" — preferring to confirm before executing. Sonnet does not exhibit this after the round-two fix. In real pipeline operation, run-implementation and run-process-change always pass valid modes; the F1 condition cannot be produced by a conforming orchestrator. G4 is more plausible but still requires a state the orchestrator's sequencing prevents.
**Current mitigation:** Anti-rationalization rule "Thinking 'the input is ambiguous, I should ask the user what they meant'? Stop." The rule is present; Opus disregards it on the strongest edge inputs.
**Potential escalation:** If orchestrator bugs or human-driven dispatch start producing invalid modes in practice, consider (a) moving the placeholder write to a pre-mode-parse step with a mode-agnostic target, or (b) adding a structural "if you are about to emit natural-language prose, stop and write the result file" rule. Not yet justified — orchestrators dispatch deterministically and the conditions producing this behavior do not arise in the normal pipeline.

### git-tool PR-mode Data Flow assertion requires clean feature branch (test-environment limitation)

**Affects:** git-tool testing (not the agent itself)
**Observed in:** git-tool testing, G5 across both runs and both models. Assertion looks for "Data Flow" in agent stdout when PR mode runs with trust ON and `impl-describe-flow.txt` present. The agent correctly fails at step 4 (current branch must start with `feature/`, working tree must be clean) — the test repo is on `active-dev` with modified tracked files.
**Behavior:** The agent is following its contract; the test environment cannot reach the step where the Data Flow section is composed. This is an environment constraint, not an agent defect.
**Current mitigation:** None needed for the agent. Testing for PR-mode body assembly requires a clean feature branch with push access, which the unit-style harness does not set up.
**Potential escalation:** If PR-mode body composition becomes worth testing in isolation, generate a fixture that checks out a scratch `feature/test-*` branch before invoking the agent, then restores the prior branch after. Not yet justified — the assembly is simple concatenation of known fields, and integration testing against a real change will cover the real path.
