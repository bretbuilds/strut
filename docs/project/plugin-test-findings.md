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

- [x] **Spec write↔review loop convergence (redesign).** ~~Two runs of the same simple change converged differently (3 iterations vs. 5+ then failure). Each iteration surfaced *different* concerns (ambiguity → testability → compoundness → inheritance). That's whack-a-mole, not convergence.~~ Fixed across four files (templates + dogfood mirrors): `run-spec-refinement` archives failed iterations to `iterations/iter-N-{spec,review}.json` and writes `spec-refinement-result.json` on exhaustion; `spec-write` reads `human-guidance.md` (top priority) + `iterations/` + `iterations-archive/round-*/` and follows explicit precedence; `spec-review` reads its own prior reviews + `human-guidance.md` and applies ratchet calibration (don't re-flag fixed concerns, bias toward passing on later iterations); `run-process-change` adds a `spec_stuck` gate that fires on exhaustion, displays one-line iteration summaries, and parses `guidance:` (move iterations/ → iterations-archive/round-N/, write human-guidance.md, fresh 5-iter budget) or `abort`. Verification will come from the next test run that hits the spec cycle. **Original problem details follow for context:** root cause was that `spec-write` read only the latest `spec-review.json` and `spec-review` had no memory of prior passes — so each iteration could fix the newest concern while regressing on older ones.

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

- [x] **Spec approval gate: render human-readable spec.** ~~Currently the gate prints file paths and asks the human to read raw JSON.~~ Fixed in `templates/skills/run-process-change/SKILL.md` Step 6 (mirrored in `.claude/skills/`): the gate now instructs Claude to read `spec.json` and render a markdown summary (what / user_sees / acceptance criteria with type and Given/When/Then / files to modify / out of scope / tasks) inside the gate block. Raw file paths still appear at the bottom for users who want to view deeper detail. Scope-mismatch notes (the existing trust/decompose checks) are preserved and inserted between the summary and the response options. Verification will come from the next `/run-strut` invocation.
- [x] **`/strut:init`: detect dirty / zero-commit / DS_Store-tracked state.** ~~A repo with `git init` but zero commits passes the README's "version controlled" prereq but fails `git-tool`'s clean-tree precondition at branch creation, with no early signal.~~ Fixed in `bin/strut-install.sh` Step 0: preflight aborts with actionable guidance for three states — not a git repo, zero commits on current branch, or dirty tree (with `git status --short` output). Skill body (`skills/init/SKILL.md`) updated to instruct Claude to relay each failure mode to the user without silently fixing it. Verified against all four states (not-a-repo, zero-commits, dirty, and clean).
- [x] **`/strut:init`: append OS metadata to `.gitignore`.** ~~Add `.DS_Store`, `Thumbs.db` as a baseline. If `.DS_Store` is already tracked, run `git rm --cached` as part of init.~~ Fixed in `bin/strut-install.sh` Steps 9–10: `.DS_Store` and `Thumbs.db` appended under an `# OS metadata` section header, idempotent on re-run; tracked `.DS_Store` files (at any depth) are untracked via `git rm --cached`. Verified end-to-end on a temp repo with `.DS_Store` committed at multiple levels.

### Medium priority — documentation / polish

- [x] **README: install command is wrong.** ~~Says `claude plugin add github:bretbuilds/strut` — should be `claude plugin install`.~~ Fixed: now documents the two-step `marketplace add` + `install` flow that actually works.
- [x] **README prerequisites are incomplete.** ~~Says "version controlled" but the pipeline actually requires "clean working tree + at least one commit on main."~~ Fixed: prereq now explicitly calls out the clean-tree + initial-commit requirement and that `.DS_Store` counts as dirty.
- [x] **NOT APPLICABLE rules files: leave shipped, treat as dormant (not deleted, not warned).** ~~Current init flow keeps `strut-database.md` around for non-DB projects with globs scoped to nonexistent paths. Doctor correctly flags this as dead weight. Init should delete the file outright when it determines the template doesn't apply.~~ Original framing was wrong — a rules file with non-matching globs doesn't load into context, doesn't count toward the always-loaded threshold, and auto-activates the moment matching paths exist. The "dead weight" was a phantom problem created by the doctor's old warning, not by the file itself. Fixed by treating dormancy as a normal state, not a defect:
  - `skills/init/SKILL.md` Step 2.4 simplified: update globs only if you can confidently detect data-layer paths; otherwise leave the file alone. No deletion, no manifest gymnastics, no NOT APPLICABLE notice in the body.
  - `skills/init/SKILL.md` Important section: explicit "do NOT delete shipped rules files" — they're dormant, not broken, and the user will need them if their project grows the matching surface.
  - `skills/doctor/SKILL.md` Section 3: scoping check now distinguishes "actively scoped" (globs match) from "dormant" (globs don't match — informational, not a warning) from "user-edited globs that don't match" (real warning, suggests a typo).
  - Net effect: a Go logger after `/strut:init` shows `strut-database.md` under "Dormant rules" in doctor output. No warning. File is available if the project later grows a database. Current init flow keeps `strut-database.md` around for non-DB projects with globs scoped to nonexistent paths. Doctor correctly flags this as dead weight. Init should delete the file outright when it determines the template doesn't apply.

### Lower priority — deferred

- [x] **Step 6b adversarial spec attack gate: render human-readable spec.** ~~Used the same raw-JSON style we fixed for spec approval.~~ Fixed: now renders the same `what` / `user_sees` / `criteria` / `files` / `out_of_scope` / `tasks` summary as Step 6 (spec approval), so the human can see what they're about to attack adversarially. Raw file paths preserved for deeper inspection. Synced to dogfood mirror.
- ~~**PR review gate**: not changed. The artifact (PR diff) lives on GitHub, not in pipeline files. The current "PR: <url>" pointer is the right shape — rendering local content there wouldn't add what GitHub already provides.~~





- [ ] **Resume-from-failure paths.** Late-stage failures (e.g., implementation/branch precondition) currently force a full Read Truth → spec restart, redoing scan, classification, gate, and the entire spec cycle (which itself isn't converging reliably). Architecture only supports resume from `"blocked"` gates, not from `"failed"` states.
- [ ] **Trim total constraint count.** STRUT ships at 79 total / 60 always-loaded out of the box — over its own Curse of Instructions ceiling. Doctor identified concrete consolidations: operating-rules 14–16 (When Things Go Wrong), pipeline 8–11 (File Contracts), architecture 6–8 (Naming Conventions).

## Notes

- The plugin install/init/doctor layer is solid after the fixes above. The pipeline runtime layer (spec convergence, gate UX, failure recovery) is where the remaining work lives.
- Doctor's diagnostics genuinely caught real issues (template mismatch, dead scoping, over-ceiling counts). It's working as designed; the findings reflect template-fit problems, not doctor bugs.
- Stack agnosticism is partially proven: install/init/doctor handled Go cleanly. Pipeline runtime never reached the language-specific work, so we can't yet claim the pipeline itself is stack-agnostic — only that the bootstrap is.
