# [Agent Name]

<!-- Template for authoring a worker agent. Agents receive isolated context, do one
     task, and write one result file. If you're authoring an orchestrator that
     dispatches other components, use skill-template.md instead.

     Before writing, read the "Authoring guidance" section at the bottom of this file. -->

## Purpose
[One sentence: what this agent does and why it exists]

## Dispatched By
[Parent skill name — e.g., "run-spec-refinement"]

<!-- Most agents have a single dispatcher. Multi-mode agents (e.g., git-tool has three modes:
     branch, commit, pr) are dispatched by different parents at different points; see the
     authoring guidance for how to structure multi-mode agents. -->

## Input Contract
### Files Read
- `.strut-pipeline/[filename]` — [what it contains, why this agent needs it]
- `.claude/rules/[filename]` — [which rules constrain this agent's behavior, if any]

### Other Inputs
- [any non-file inputs: classification.json fields, branch name, diff, etc.]

## Output Contract
### Result File
- `.strut-pipeline/[path-to-result].json`

### Result Schema

Minimal base shared by all agents:

```json
{
  "skill": "[agent-name]",
  "status": "[see Status Values below]",
  "summary": "..."
}
```

Additional fields are agent-specific. Two common shapes:

**Content-producing agents** (spec-write, spec-review, review-scope, review-criteria-eval, etc.) — produce a content artifact alongside the result file:

```json
{
  "skill": "[agent-name]",
  "status": "passed",
  "output_file": ".strut-pipeline/spec-refinement/spec.json",
  "summary": "...",
  "issues": []
}
```

**Action-taking agents** (git-tool, impl-write-code, build-check) — perform an action and report what happened:

```json
{
  "skill": "git-tool",
  "status": "created",
  "branch_name": "feature/add-response-flow",
  "summary": "..."
}
```

### Status Values
<!-- Declare the exact status values this agent returns and what each means.
     See docs/strut-architecture/core-path-architecture.md Section 3 Complete File Contract Table
     for all current agents' status values. Common ones: -->

- `passed` — [what this means for this agent]
- `failed` — [what this means, what's in summary]
- [agent-specific values, e.g., `created` / `exists` for git-tool (branch), `committed` for git-tool (commit), `opened` for git-tool (pr)]

### Content Files (if the agent produces a separate content artifact)
- `.strut-pipeline/[content-filename]` — [what it contains, who consumes it]

## Modifier Behavior
<!-- Only include this section if the agent's behavior varies by modifier.
     Most agents have uniform behavior regardless of modifiers. -->

| Modifier | Behavior |
|----------|----------|
| Standard | [default behavior] |
| Trust ON | [e.g., populate must_never[] from rules] |
| Decompose ON | [e.g., process single task from tasks[], not full spec] |

## Algorithm
[Numbered sequential steps. Not principles — steps. The model follows these in order.]

1. [action]
2. [action]
3. ...

## Plan Mode Directive
<!-- Only for agents where jumping straight to output is the most dangerous failure mode.
     The current architecture specifies three agents with plan mode directives:
     - spec-write: plan criteria, out_of_scope entries, and implementation_notes before drafting
     - impl-write-tests: plan each test's assertion, fixture, and expected outcome before writing
     - impl-write-code: plan each file change and how it connects to the test it satisfies
     See docs/strut-architecture/core-path-architecture.md Section 1 for the exact directive wording for each.
     Remove this section if the agent doesn't need a plan-mode directive. -->

Before producing the result file, write a numbered plan:
- [what to plan — specific to this agent's output]
- [what to plan]

Then execute the plan.

## Anti-Rationalization Rules
<!-- Only include rules that address observed failures. Start without this section;
     add rules reactively when you see a specific failure mode during testing. -->

- Thinking about [bad thing]? Stop. [What to do instead.]
- Do NOT [prohibited action]. [Why.]

## Boundary Constraints
- Does NOT write: files outside those declared in the Output Contract
- Does NOT read: files outside the Input Contract
- Does NOT: [other agent-specific prohibitions]

## Failure Behavior
- On failure: write result file with `"status": "failed"` and details in `summary`. Exit.
- Do NOT retry. [Parent skill name] manages retries.
- Do NOT suggest fixes. Do NOT ask how to proceed. Stop and wait.

## Explore Ban
The Explore agent is NOT used. Do not invoke Claude Code's Explore subagent between steps.

---

## Authoring guidance

Read this before writing. These are validated observations from building and testing pipeline agents.

### Size and context budget

- Agents get isolated context per dispatch, so their budget is less constrained than skills. But directive cost still applies: every instruction competes with every other.
- **Target: under 300 lines** for the agent body. Beyond that, consider whether the agent is actually two agents.
- Supporting files (`examples/`, `references/`) load on demand. Use them to keep the agent body lean.
- **Examples: 250–300 lines max.** If testing surfaces context pressure, trim to 3 representative cases (one positive, one negative, one edge) rather than exhaustive sets.
- **One level deep references only.** Agent → file.md is fine. Agent → file.md → another-file.md won't fully load.

### Platform constraint: agents cannot spawn agents

In Claude Code, agents are worker contexts dispatched by skills. Agents cannot themselves dispatch other agents. If your agent design seems to need sub-delegation, that's a signal the work belongs in a sub-orchestrator skill, not a single agent.

### Multi-mode agents

Some agents have multiple modes dispatched by different parents at different points — `git-tool` is the canonical example, with branch / commit / pr modes. For multi-mode agents:

- Use one agent file covering all modes
- Document inputs and outputs per mode in the Input/Output Contract sections (e.g., "branch mode reads X, writes Y; commit mode reads Z, writes W")
- The Dispatched By section lists all parent orchestrators and which mode each dispatches
- Status values may differ per mode (e.g., git-tool branch returns `created | exists`, commit returns `committed`, pr returns `opened`)

### What makes agents actually work

- **`rm -f` before writing any `.strut-pipeline/` file** prevents reading stale state from previous runs.
- **Anti-rationalization blocks ("Thinking X? Stop.")** prevent more failures than polite instructions. Use direct interception, not polite phrasing. Add only when you observe the failure — each one is an expensive condition constraint.
- **Numbered algorithm steps prevent models from substituting their own logic.** Prose descriptions get reinterpreted.
- **Failure actions must say "stop and wait," not "ask how to proceed."** The latter produces bypass options.
- **Model and tools are declared in frontmatter only.** Do not add ## Model or ## Tools sections to the agent body — frontmatter is the source of truth. Restating in the body creates drift risk and wastes tokens.
- **Observations from testing go to `docs/strut-architecture/model-limitations-log.md`**, not in the agent file. Agent files contain only directives that shape model behavior — not commentary, rationale, or historical notes.

### What does NOT work (tested and removed)

- **"First output line must be [X]"** — non-observable. When agents are invoked via `--agent`, the parent receives only the final assistant message. Intermediate output and tool calls are invisible. Directives targeting observable output formatting cannot be verified by orchestrators and waste directive budget.
- **Gotchas sections** — historical notes for human readers, processed by the model on every dispatch. Token cost with no behavioral benefit. Observations belong in `docs/strut-architecture/model-limitations-log.md`.
- **## Model and ## Tools body sections** — duplicate frontmatter. Drift risk. Removed from all agents.

### Mechanical enforcement over directive

Before writing a new directive, check whether it can be enforced at a lower layer:

- **Tool restrictions** → frontmatter `tools:` field, not a directive
- **Model selection** → frontmatter `model:` field, not a directive
- **Sequential constraints** → orchestrator dispatch order, not a directive
- **File boundary constraints** → possible to check at orchestrator level, not purely directive

Directives are the most expensive layer. Use them only when lower layers can't enforce what you need.

### Format

- Plain markdown. No XML tags. Claude 4.x models respond better to clear markdown than XML structuring.
- Keep the agent body focused on core instructions. Move examples and detailed references into supporting files.

### Protecting tested agents

Opus will attempt to "improve" a working agent by restructuring it — removing anti-rationalization language, rewriting algorithm steps, adding unrequested capability. Do not allow this. A tested agent is frozen. Changes go through re-testing.

If Opus restructures an agent during a session, revert to the last tested version immediately.