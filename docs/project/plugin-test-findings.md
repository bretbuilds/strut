# Plugin Test Findings — 2026-05-02

First end-to-end test of the plugin format against an external Go project (`charmbracelet/log` cloned into `~/dev/projects/test-project`). Test goal: prove `claude plugin install strut` → `/strut:init` → `/run-strut "<change>"` works on a non-Node, non-Next.js codebase (stack agnosticism).

The test change: *"add a `WithDuration(start time.Time)` helper that returns a child logger with an `elapsed` key, following the existing `With`/`WithPrefix` pattern."*

## Outcome

- **Plugin install:** works, but only after several manifest fixes (see Fixed below).
- **`/strut:init`:** works on a Go project. Stack detection, settings merge, CLAUDE.md append all functional.
- **`/strut:doctor`:** works. Surfaced the framework's own constraint-count violation (over its own ceiling out of the box).
- **`/run-strut`:** **did not complete.** Two precondition failures at branch creation, and one 5-iteration spec-loop failure. Pipeline never reached implementation.

## Already fixed in this test run

- [x] Added `.claude-plugin/marketplace.json` so the plugin is discoverable as a self-hosting marketplace
- [x] Reduced `plugin.json` `commands` array to only the bootstrap commands (`init`, `doctor`, `update`). Earlier attempt to expose pipeline skills directly was wrong — pipeline skills only exist in a project after `/strut:init` copies them in.
- [x] Doctor: separate always-loaded vs scoped constraint counts; threshold check fires only on always-loaded
- [x] Init: stop stripping `globs:` from rules files flagged NOT APPLICABLE (was promoting them from scoped to always-loaded — opposite of intent)

## Still to fix

### High priority — blockers found in this test

- [ ] **Spec write↔review loop convergence (redesign).** Two runs of the same simple change converged differently (3 iterations vs. 5+ then failure). Each iteration surfaced *different* concerns (ambiguity → testability → compoundness → inheritance). That's whack-a-mole, not convergence. Root cause: `spec-write` reads only the *latest* `spec-review.json` as feedback — it has no memory of what was rejected in iter 1 and 2, so it fixes the latest concern while regressing on earlier ones. `spec-review` has the same blindspot — it can't ratchet against prior passes.

  Three-layer fix:

  **Layer 1: preserve iteration history every run.** `run-spec-refinement` writes per-iteration files before re-dispatching:

  ```
  .strut-pipeline/spec-refinement/
    spec.json                       # current draft
    spec-review.json                # current review
    iterations/
      iter-1-spec.json
      iter-1-review.json
      iter-2-spec.json
      iter-2-review.json
      ...
  ```

  Both agents read `iterations/` as input. `spec-write` sees the full rejection trail. `spec-review` ratchets — only flags issues *worse* than the prior pass.

  **Layer 2: on 5-iter failure, escalate to a `spec_stuck` gate, not silent termination.** Show the human a summary of what each iteration was rejected for. Human responses:
  - `guidance: <text>` — extend budget by 3 with the human's clarification as top-priority input (above iteration history)
  - `force <iter-N>` — accept iteration N's spec as-is and proceed
  - `abort` — stop

  **Layer 3: spec-write feedback precedence becomes** `human-guidance.md` > `iterations/` > current change request.

  Files to change:
  - `templates/skills/run-spec-refinement/SKILL.md` — add iteration history saving, add `spec_stuck` escalation
  - `templates/agents/spec-write.md` — read `iterations/` + `human-guidance.md`, document precedence
  - `templates/agents/spec-review.md` — read prior `iter-N-review.json`, ratchet
  - `templates/skills/run-process-change/SKILL.md` — handle `spec_stuck` gate, parse `guidance:` / `force <N>` / `abort`
  - `templates/skills/run-strut/SKILL.md` — display the `spec_stuck` gate

- [ ] **Spec approval gate: render human-readable spec.** Currently the gate prints file paths and asks the human to read raw JSON. Update `templates/skills/run-process-change/SKILL.md` (around lines 295–315) so session Claude reads `spec.json` and renders a markdown summary (what / user_sees / criteria / files / out-of-scope / tasks) before showing the prompt.
- [ ] **`/strut:init`: detect dirty / zero-commit / DS_Store-tracked state.** A repo with `git init` but zero commits passes the README's "version controlled" prereq but fails `git-tool`'s clean-tree precondition at branch creation, with no early signal. Init should detect and either fix or halt with guidance.
- [ ] **`/strut:init`: append OS metadata to `.gitignore`.** Add `.DS_Store`, `Thumbs.db` as a baseline. If `.DS_Store` is already tracked, run `git rm --cached` as part of init. We hit this exact wall twice in one session on macOS.

### Medium priority — documentation / polish

- [x] **README: install command is wrong.** ~~Says `claude plugin add github:bretbuilds/strut` — should be `claude plugin install`.~~ Fixed: now documents the two-step `marketplace add` + `install` flow that actually works.
- [x] **README prerequisites are incomplete.** ~~Says "version controlled" but the pipeline actually requires "clean working tree + at least one commit on main."~~ Fixed: prereq now explicitly calls out the clean-tree + initial-commit requirement and that `.DS_Store` counts as dirty.
- [ ] **NOT APPLICABLE rules files: delete rather than leave dormant.** Current init flow keeps `strut-database.md` around for non-DB projects with globs scoped to nonexistent paths. Doctor correctly flags this as dead weight. Init should delete the file outright when it determines the template doesn't apply.

### Lower priority — deferred

- [ ] **Resume-from-failure paths.** Late-stage failures (e.g., implementation/branch precondition) currently force a full Read Truth → spec restart, redoing scan, classification, gate, and the entire spec cycle (which itself isn't converging reliably). Architecture only supports resume from `"blocked"` gates, not from `"failed"` states.
- [ ] **Trim total constraint count.** STRUT ships at 79 total / 60 always-loaded out of the box — over its own Curse of Instructions ceiling. Doctor identified concrete consolidations: operating-rules 14–16 (When Things Go Wrong), pipeline 8–11 (File Contracts), architecture 6–8 (Naming Conventions).

## Notes

- The plugin install/init/doctor layer is solid after the fixes above. The pipeline runtime layer (spec convergence, gate UX, failure recovery) is where the remaining work lives.
- Doctor's diagnostics genuinely caught real issues (template mismatch, dead scoping, over-ceiling counts). It's working as designed; the findings reflect template-fit problems, not doctor bugs.
- Stack agnosticism is partially proven: install/init/doctor handled Go cleanly. Pipeline runtime never reached the language-specific work, so we can't yet claim the pipeline itself is stack-agnostic — only that the bootstrap is.
