# Test Categories

Generate tests in these categories. Not every category applies to every skill or agent — skip categories that don't apply and note why. Categories A–E are structural and apply broadly. F is model-specific regression. G is always needed — it's where the skill-specific judgment lives.

## Category A: Happy path — correct input produces correct output

**A1: Normal invocation with valid fixtures**
- Create properly-formed input files in `.pipeline/`
- Invoke the skill/agent
- Assert: result file exists, valid JSON, status = "passed" (or the skill's success status), `output_file` field points to real file

**A2: Per-modifier behavior (if skill/agent varies by modifier)**
- For each modifier combination the skill/agent handles:
  - Set `classification.json` modifiers accordingly
  - Invoke
  - Assert: behavior matches the Modifier Behavior table in the SKILL.md or agent file

**A3: Content correctness spot-check**
- After a successful run, read the content file the skill/agent produced
- Assert: contains expected structural elements (e.g., Given/When/Then for criteria, numbered steps for spec, per-criterion status for reviewers)

## Category B: Failure handling — bad input produces correct failure

**B1: Missing input file**
- Do NOT create a required input file
- Invoke
- Assert: result file exists, status is a failure status, `summary` explains what's missing
- Assert: no partial output files were created

**B2: Malformed input file**
- Create input file with invalid JSON or missing required fields
- Invoke
- Assert: result file exists with failure status, skill/agent did not crash silently

**B3: Empty pipeline directory**
- Start with completely empty `.pipeline/`
- Invoke
- Assert: result file exists with clear failure message, not a stall or hallucinated input

## Category C: Boundary constraints — stays in its lane

**C1: Does not write files outside its contract**
- List all files in `.pipeline/` before and after invocation
- Assert: only files listed in the output contract were created or modified
- Assert: no files in `.claude/rules/` were modified
- Assert: no files outside `.pipeline/` were created
- When generating the assertion via `find .pipeline`, exclude the test script itself (`test-${COMPONENT}.sh`) and any per-test output file (e.g., `test-c1-output.txt`) — both live in `.pipeline/` and are fixtures, not agent output

**C2: Does not dispatch prohibited components (skills only)**
- Check the skill's output and logs for evidence of dispatching components outside its declared list
- Assert: only components in the `Dispatches` list were invoked

**C3: Does not read files outside its input contract**
- Create decoy files in `.pipeline/` that should NOT be read
- Invoke
- Assert: output shows no evidence of reading decoy content

## Category D: Behavioral compliance

**D1: First output line**
- SKIP for agents. Agent output via `--agent` invocation returns only the final assistant message — intermediate output is non-observable by the parent. First-output-line directives were tested and removed from all agents as non-enforceable.
- For skills invoked interactively, this may be observable but is not load-bearing for orchestrator routing (orchestrators route on file status, not text output).

**D2: Announcement before action**
- Same limitation as D1. Non-observable via `--agent` invocation. Skip for agents.

**D3: Timestamp freshness (if applicable)**
- If the skill/agent writes timestamps
- Assert: timestamp is within 60 seconds of actual current time
- Catches timestamp reuse from input files

**D4: No Explore agent**
- Assert: output contains no evidence of Explore agent invocation
- Catches Explore being launched between steps

## Category E: Pipeline handoff compatibility

**E1: Result file schema compliance**
- Assert: result file has all required fields per the output contract
- Assert: status is one of the values declared for this component
- Assert: arrays are arrays (even if empty)

**E2: Stale state handling**
- Pre-populate `.pipeline/` with result files from a previous run
- Invoke
- Assert: skill/agent uses `rm -f` and writes fresh results, not appending to stale files

**E3: Re-invocation idempotency**
- Run twice with the same inputs
- Assert: second run produces equivalent output (not duplicated or corrupted)

## Category F: Model-specific regression tests

These test for failure modes that have been observed in specific model generations. The specific findings age as models improve, but the tests remain valuable because they surface whether new model generations still exhibit the same failures.

**F1: Prescriptive compliance**
- Verify the model follows the numbered algorithm or dispatch sequence in order
- Check for substitution of its own logic for the prescribed sequence
- Historically the #1 Sonnet failure mode for process skills

**F2: Process compliance**
- Verify no skipping of steps
- Verify no unrequested analysis or exploration added
- Verify no Explore agent launched
- Historically the #1 Opus failure mode for pipeline skills

**F3: Cross-model output consistency**
- Verify both models produce structurally identical output
- Record any divergence in extra fields, formatting, or commentary as a compatibility issue

## Category G: Domain-specific edge cases

These are NOT generic infrastructure checks — they test boundary conditions specific to THIS component's purpose. Generate 3–5 scenarios by asking:

- What's the weirdest valid input this could receive?
- What's the most ambiguous case where the correct output is non-obvious?
- What input would make the correct behavior non-obvious?
- What happens at the boundary between "this handles it" and "this should escalate"?

**G1–G5: Component-specific scenarios**
- For each: describe the edge case, create a fixture reproducing it, state the correct behavior and why, write assertions to verify.

Examples of what these look like for different components:

- `spec-write`: Intent with `must_never` = empty array (trust OFF) — does it still generate at least one positive criterion? (Answer: yes, at least one user-facing or data-facing criterion.)
- `review-scope`: Diff contains a file not in the impact scan but the change is a legitimate new dependency — does it flag as scope creep or recognize it? (Answer: flag it — the reviewer is conservative. The flag is reviewed at the gate.)
- `spec-review`: Spec with exactly 3 tasks where task 2 depends on task 1's output — does Phase 3 (decomposition validation, decompose ON only) flag the dependency? (Answer: flag it — each task must be independently testable.)
- `review-security`: Diff adds a query that joins through a table without its own RLS policy — does it catch the pivot bypass? (Answer: must catch it — this is the specific RLS bypass pattern from security.md.)
- `truth-classify`: Change request mentions "updating a button label" but the repo scan reveals the button triggers an auth flow — does classification escalate to trust ON? (Answer: yes — scan reveals auth involvement, trust modifier activates.)

## Lessons learned — apply to all test sessions

### Patterns to always test for

Model-specific failure modes have been observed historically. Even if specific findings shift with model generations, testing for these patterns is how we'd catch regressions in a new generation:

- **Alternative logic substitution when instructions aren't prescriptive.** Test F1 catches this.
- **Timestamp reuse from input files.** Test D3 catches this.
- **Explore agent launched between steps.** Test D4 catches this.
- **Unrequested analysis added.** Test F2 catches this.
- **Revision introduces new defects in unflagged content.** Observed in spec-write — each revision pass can drift criteria that weren't named in feedback. Monitor across revision cycles.

### Structural patterns that must hold

- `rm -f` before writing `.pipeline/` files. Test E2 catches stale state.
- Result file has all fields declared in the output contract. Test E1 catches this.
- Agents do not dispatch. Skills dispatch only their declared list. Test C2 catches this.
- Orchestrators route on `status` fields only, never on content fields.

### Patterns tested and removed (do not re-add)

- **"First output line must be [X]"** — non-observable via `--agent` invocation. Parent receives only the final assistant message. Directive was removed from all agents after testing proved it non-enforceable across three fix attempts (directive, structural bash, final-message framing). See `docs/strut-architecture/model-limitations-log.md`.
- **Gotchas sections** — historical notes consumed tokens on every dispatch with no behavioral benefit. Observations go to `docs/strut-architecture/model-limitations-log.md`.
- **## Model and ## Tools body sections** — duplicated frontmatter, created drift risk. Frontmatter is the source of truth.

### Testing protocol

- Tests run under both Sonnet and Opus — a skill that passes on one may fail on the other
- Fix issues immediately as found in a separate session, then re-test the failing case
- A component is not ready until it passes ALL applicable categories on BOTH models