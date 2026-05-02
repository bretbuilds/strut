# Pre-Build Architecture Decisions

Four decisions that affect multiple agents and should be locked in before building starts.

---

## 1. Spec JSON Schema

The spec is the central contract. spec-write produces it. Five agents consume it. Each needs different things.

### What each consumer needs

| Consumer | What it reads from spec | Why |
|----------|----------------------|-----|
| spec-review | criteria, must_never, out_of_scope | Check ambiguity, testability, completeness, gaps |
| impl-write-tests | criteria, must_never, tasks[].criteria_ids | Write one test per criterion, one negative test per must_never, scoped to task |
| impl-write-code | implementation_notes, criteria (for understanding) | Know which files to modify, which patterns to follow, what the change should do |
| review-scope, review-criteria-eval | criteria, must_never, out_of_scope | Check diff matches scope, each criterion satisfied, must_never tested |
| update-capture | what, criteria (for summary) | Describe what was decided and compare against what was built |

### The schema

```json
{
  "skill": "spec-write",
  "status": "drafted",
  "what": "The change description, echoed from classification",
  "user_sees": "What the user observes after the change, from intent.json",

  "criteria": [
    {
      "id": "C1",
      "given": "A published update with action items",
      "when": "The recipient clicks respond on an action item",
      "then": "A receipt is created with the response content and timestamp",
      "type": "positive"
    },
    {
      "id": "MN1",
      "given": "A recipient from org A",
      "when": "They attempt to respond to an action item from org B",
      "then": "The response is rejected and no receipt is created",
      "type": "negative",
      "source": "must_never: cross-tenant data access on action_responses"
    }
  ],

  "implementation_notes": {
    "files_to_modify": [
      { "path": "app/lib/actions/respondAction.ts", "reason": "Add response handler" }
    ],
    "patterns_to_follow": [
      "All server actions use createClient() from lib/supabase/server.ts"
    ],
    "files_to_reference": [
      { "path": "app/lib/actions/publishAction.ts", "reason": "Same mutation pattern" }
    ]
  },

  "out_of_scope": [
    "Email notification on response — separate change",
    "Response editing after submission — not in V1"
  ],

  "tasks": [
    {
      "id": "task-1",
      "description": "Implement response action with receipt creation",
      "criteria_ids": ["C1", "C2", "MN1"]
    }
  ]
}
```

### Design decisions in this schema

**Criteria use Given/When/Then format.** Each criterion is independently testable — a test can directly map to one Given/When/Then. This is BDD format, widely understood, and naturally produces assertions.

**must_never entries are folded into criteria as negative type.** Rather than a separate must_never array, each must_never becomes a criterion with `"type": "negative"` and a `"source"` field tracing it back to the intent. This means impl-write-tests treats all criteria uniformly — positive criteria get positive tests, negative criteria get negative tests. spec-review checks all criteria the same way. No special handling needed downstream.

**implementation_notes are copied from the scan, not re-derived.** spec-write reads `.strut-pipeline/truth-repo-impact-scan-result.json` and copies the relevant parts. This grounds the spec in actual codebase evidence rather than the spec agent inventing file paths.

**out_of_scope requires at least one entry.** Forces spec-write to think about boundaries. spec-review checks this.

**tasks[] is always present, even for decompose OFF.** Decompose OFF = one task containing all criteria_ids. Decompose ON = up to 5 tasks, each with a subset. The schema is identical in both cases — only the count changes. This means impl-write-tests and run-implementation don't need to know whether decompose is ON or OFF — they iterate over tasks and process each one.

**3-7 criteria total (unenforced — revisit once architecture is built).** The bounded spec concept comes from research (Stanford/UC Berkeley, referenced in `.claude/rules/strut-methodology.md`) and the Curse of Instructions principle suggests fewer constraints improve compliance. The specific range 3-7 is a judgment call, not a research finding. Currently no agent enforces this — spec-write has no minimum or maximum, and spec-review doesn't reject based on count. Revisit whether this needs enforcement once real spec output is observed in practice, and if so, where (spec-write directive? spec-review check? neither?).

---

## 2. Pipeline Cleanup Between Runs

### The problem

If a previous run left files in `.strut-pipeline/spec-refinement/` or `.strut-pipeline/implementation/`, a new run for a different change could read stale data.

### The decision

**run-process-change cleans its own directories at the start of a new run.** A new run is distinguished from a resume by checking whether `process-change-state.json` matches the current change (see Decision 3).

Cleanup sequence for a new run:
```bash
rm -rf .strut-pipeline/spec-refinement .strut-pipeline/implementation .strut-pipeline/build-check .strut-pipeline/update-truth
rm -f .strut-pipeline/process-change-state.json .strut-pipeline/git-pr-result.json
mkdir -p .strut-pipeline/spec-refinement .strut-pipeline/implementation/task-1 .strut-pipeline/build-check .strut-pipeline/update-truth
```

For a resume: skip cleanup, read state, pick up where you left off.

**Read Truth already handles its own cleanup.** run-read-truth step 1 deletes its output files before starting. This stays unchanged.

**Classification log is append-only.** `.strut-pipeline/classification-log.md` is never deleted — it's the history of all classifications across runs.

---

## 3. Resume vs. New Run

### The problem

When the human invokes `/run-strut` after a previous run paused at a human gate, the pipeline needs to know: is this continuing the paused run, or starting a different change?

### The decision

**Compare `what` fields.** run-process-change reads `process-change-state.json` and `classification.json`. If both exist and the `what` field matches, it's a resume. Otherwise, it's a new run.

```
if process-change-state.json does NOT exist:
  → new run (clean start)

if process-change-state.json exists:
  compare process-change-state.what vs classification.json.what
  
  if they match:
    → resume (read state, skip completed stages, continue from next pending)
  
  if they don't match:
    → new run (previous run abandoned, clean Process Change directories, start fresh)
```

**run-strut always runs Read Truth first,** even on resume. This means classification.json is always fresh. The `what` field comes from the human's input to `/run-strut`, so matching it against the state file's `what` is a reliable signal.

**Edge case: human tweaks the wording slightly.** "/run-strut 'Add RLS to action_responses'" vs "/run-strut 'add rls to action responses'." These are the same change but the `what` strings differ. Decision: exact match. If the wording changes, it's treated as a new run. The human can always choose to start fresh by rewording, and choosing to resume by using the exact same phrasing. This is simple and predictable.

---

## 4. PR Rejection Path

### The problem

When the human rejects the PR, the issue might be in the implementation (code is wrong) or in the spec (criteria are wrong). The current flow only re-dispatches implementation.

### The decision

**The human chooses where to loop back.** At the PR rejection gate, run-process-change asks:

```
PR rejected. Where should the pipeline loop back?

  - "spec" → re-enter spec refinement with your feedback
  - "implementation" → re-run implementation against the same spec with your feedback
  - "abort" → stop the pipeline entirely

Feedback: [your feedback here]
```

**If spec:** run-process-change writes feedback to `.strut-pipeline/pr-rejection-feedback.json`, wipes implementation and build-check directories (the implementation was based on the old spec), and re-dispatches run-spec-refinement. spec-write reads the feedback file and revises. The spec cycle (write → review) runs again. After spec approval, implementation restarts from scratch against the new spec.

**If implementation:** run-process-change writes feedback to `.strut-pipeline/pr-rejection-feedback.json` and re-dispatches run-implementation. The impl-write-code agent reads the feedback alongside the existing spec and review chain results. This is the simpler path — same spec, revised code.

**If abort:** run-process-change writes `{ "status": "aborted" }` to process-change-state.json and stops.

**State file tracks the rejection:**
```json
{
  "status": "blocked",
  "gate": "pr_rejection",
  "loop_target": "spec",
  "feedback": "The criteria don't cover the case where..."
}
```

This is simpler than automatic detection of whether the problem is spec or implementation. You just reviewed the PR — you know where the problem is.
