# [Skill Name]

<!-- Template for authoring a skill (orchestrator). Skills dispatch agents and check
     file results. They do not produce reasoning output. If you're authoring a worker
     that does actual task work, use agent-template.md instead.

     Before writing, read the "Authoring guidance" section at the bottom of this file. -->

## Purpose
[One sentence: what this skill orchestrates and why it exists]

## Category
[SUB-ORCHESTRATOR | PHASE ORCHESTRATOR | TOP-LEVEL ORCHESTRATOR]

## Dispatched By
[Parent orchestrator name, or "human directly (via /run-strut)"]

## Dispatches
[List of agents and sub-orchestrators this skill can dispatch. Exhaustive — the skill does not dispatch anything outside this list.]

## Input Contract
### Files Read
- `.pipeline/[filename]` — [what it contains, why this skill needs it]
- `classification.json` — [if this skill's behavior varies by modifier]

### Modifier Behavior
| Modifier | Behavior |
|----------|----------|
| Standard (trust OFF, decompose OFF) | [dispatch sequence] |
| Trust ON | [what changes: e.g., insert review-security step] |
| Decompose ON | [what changes: e.g., loop per task in tasks[]] |
| Both ON | [describe combined behavior — may be the union of trust ON and decompose ON, or may add emergent behavior not present in either alone, e.g., run-process-change's adversarial spec attack under guarded-decompose] |

## Output Contract
### State File
<!-- Only if this skill manages pipeline state (e.g., run-process-change, run-implementation).
     The state file persists across pauses at human gates, letting the orchestrator resume
     where it left off. Typical contents:
     - phase or step the skill was in when it paused
     - which sub-dispatches have completed with `passed` status
     - whether we're in a new run or resuming (compare `what` field from classification)
     - for decompose ON: completed_tasks[] and remaining_tasks[]
     Skills without pause points (like run-strut or pure sub-orchestrators) don't need one. -->

- `.pipeline/[skill-name]-state.json` — written at each pause point for resumption

### Result File
- `.pipeline/[skill-name]-result.json`

### Result Schema
```json
{
  "skill": "[skill-name]",
  "status": "[varies per skill — see docs/strut-architecture/core-path-architecture.md Section 3 Complete File Contract Table]",
  "summary": "..."
}
```

<!-- Status values vary per skill. Examples from the architecture:
     - run-process-change: blocked | passed | failed | aborted (adds `gate` field when blocked)
     - run-implementation: blocked | passed | failed
     - run-review-chain: passed | failed
     - run-build-check: passed | failed
     Declare the specific values this skill returns and what each means in prose below. -->

### Status Values
- `passed` — [what this means for this skill]
- `failed` — [what this means]
- `blocked` — [if applicable, which gate]

## Dispatch Sequence
[Numbered sequential steps. Each step is a dispatch + status-check + routing decision. Not reasoning — orchestration.]

1. [dispatch X]
2. Read `.pipeline/[X-result].json` — if `status: failed`, write result file with `status: failed`, return
3. [dispatch Y]
4. ...

## Retry Budget
<!-- Only include if this skill manages retries. Skills that retry:
     - run-spec-refinement: max 5 spec cycle iterations
     - run-implementation: max 3 retries on review chain failure
     - run-build-check: max 3 build-check/build-error-cleanup cycles
     Skills without retries (run-strut, run-update-truth, run-review-chain itself) skip this section.
     run-review-chain does not own retries — its parent run-implementation does. -->

- **Budget:** [N attempts]
- **What triggers retry:** [specific failure condition]
- **What each retry includes:** [e.g., re-dispatch failed reviewer + subsequent ones only]
- **Exhaustion behavior:** [return failed with latest feedback, escalate to human via parent]

## Anti-Rationalization Rules
<!-- Only include rules that address observed failures. Start without this section; add
     rules reactively when you see a specific failure mode during testing. -->

- Thinking about [bad thing]? Stop. [What to do instead.]

## Boundary Constraints
- Dispatches ONLY: [the list above under "Dispatches"]
- Does NOT read: agent reasoning or content fields — only status from result files
- Does NOT produce: reasoning output, analysis, summaries beyond the result file's `summary` field
- If this skill owns a retry budget, declare it in the Retry Budget section above. Otherwise retries belong to a parent orchestrator or don't apply to this skill's work.

## Failure Behavior
- On failure at any step: write the result file with `"status": "failed"`, include which step failed and why in the summary. Return.
- Do NOT retry unless this skill owns a retry budget (see above).
- Do NOT suggest fixes. Do NOT ask how to proceed. Stop and wait.

## Frontmatter

Skills are defined by SKILL.md with YAML frontmatter. Key fields:

- `name` — the slash command. Self-explanatory, max 64 characters.
- `description` — injected into the system prompt for skill matching. Specific enough that it doesn't trigger on unrelated tasks, broad enough to catch all intended uses.
- `disable-model-invocation: true` — for skills that should only run when explicitly dispatched, preventing auto-triggering on loosely matching tasks.

Skills inherit the session model (typically Sonnet). Orchestrators generally do not set `model:` in frontmatter — the session model is appropriate for dispatch-and-check work.

---

## Authoring guidance

Read this before writing. These are validated observations from building and testing pipeline skills.

### Size and context budget

- **Hard limit: 500 lines** for the SKILL.md body (Anthropic-enforced). This is a ceiling, not a target.
- **Target: ≤200 lines.** Comfort zone is 100–150 lines where adherence is strongest. Beyond 200 lines, move content to supporting files.
- Claude Code's system prompt, CLAUDE.md, and rules files consume the always-loaded instruction budget. The skill gets whatever's left — realistically 80–100 instruction slots. Write tight.
- **Supporting files** (`examples/`, `references/`) load on demand, so they don't count against the always-loaded budget. Use them to keep SKILL.md lean — but each loaded file adds to session context, so keep them focused too.
- **Examples: 250–300 lines max.** If context pressure shows up during testing, trim to 3 representative cases (one positive, one negative, one edge) rather than exhaustive sets.
- **One level deep references only.** SKILL.md → file.md is fine. SKILL.md → file.md → another-file.md won't fully load.

### Process skill vs capability skill

A binary choice before writing:

- **Process skill** (enforcing a workflow Claude wouldn't follow on its own): the prescriptive numbered steps ARE the value. "Write criteria, present them, STOP and wait for approval" must be explicit. Without it, Claude skips ahead. All pipeline orchestrators are process skills.
- **Capability skill** (teaching Claude something it already knows in your specific context): state the intent and point to an example. Don't step-by-step what Claude already knows. "Create a section component following the registry pattern in `app/lib/sections/`" — not "Step 1: create folder..."

Determine which type, then write accordingly.

### What makes skills actually work

- **`rm -f` before writing any `.pipeline/` file** prevents reading stale state from previous runs.
- **Anti-rationalization blocks ("Thinking X? Stop.")** prevent more failures than polite instructions. Use direct interception, not polite phrasing. Add only when you observe the failure — each one is an expensive condition constraint.
- **Numbered algorithm steps prevent models from substituting their own logic.** Prose descriptions get reinterpreted.
- **Failure actions must say "stop and wait," not "ask how to proceed."** The latter produces bypass options.
- **Observations from testing go to `docs/strut-architecture/model-limitations-log.md`**, not in the skill file. Skill files contain only directives that shape behavior.
- **Do not duplicate dispatched agents' model/tools in dispatch steps.** Agents' frontmatter is the source of truth. Restating "model (sonnet) and tools (Read, Grep, Glob, Bash, Write)" in the skill creates drift risk.
- **Do not duplicate classification tables or other content owned by another file.** Reference the source, don't copy it. "Keep in sync" comments are the confession that duplication exists.

### What does NOT work (tested and removed)

- **"First output line must be [X]"** — non-observable in many invocation contexts. Directives targeting observable output formatting waste directive budget when the parent can't verify them.
- **Gotchas sections** — historical notes for human readers, processed by the model on every dispatch. Token cost with no behavioral benefit. Observations belong in `docs/strut-architecture/model-limitations-log.md`.
- **Redundant "do NOT proceed" guards** that restate the previous step's precondition. Keep guards at genuine branch points (status check with two outcomes). Remove guards that follow linear steps with no branch.

### Input modes

Design for how the skill gets invoked:

- **`$ARGUMENTS`** — manual invocation (user types `/skill-name some input`)
- **Conversation context** — pipeline handoff (orchestrator provides context before dispatch)
- **File-based input** — isolated-context skills that read `.pipeline/` files, no conversation dependency

Most pipeline skills need file-based input. Manual-only skills can use `$ARGUMENTS`.

### Format

- Plain markdown. No XML tags. Claude 4.x models respond better to clear markdown than XML structuring.
- Keep SKILL.md focused on core instructions. Move examples and detailed references into supporting files.

### Protecting tested skills

Opus will attempt to "improve" a working skill by restructuring it — removing anti-rationalization language, adding agent delegation, rewriting dispatch steps. Do not allow this. A tested skill is frozen. Changes go through re-testing.

If Opus restructures a skill during a session, revert to the last tested version immediately.