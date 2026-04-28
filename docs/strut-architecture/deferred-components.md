# Deferred Components

Components designed for this architecture but not yet built. Each has a specific trigger condition — build when the trigger fires, not before. Consult this file when planning new work to check whether the component you want already has a design.

---

**Test Wisdom (`.test-wisdom/`)** — A directory for meta-knowledge about the test suite: flaky tests, false positives, coverage gaps, common failure patterns. Not the tests themselves but knowledge about the tests. Relevant when the test suite is large enough that you're losing track of which tests are trustworthy.

**Team scaling protocol** — Activation points for cross-review (N=2), domain stewardship (N=3+), spec co-authoring (N=2 for trust ON changes), weekly knowledge sync (N=2+), substrate governance (N=10+). Relevant when hiring or bringing on a collaborator.

**`passed_with_concerns` status** — A middle ground between `passed` and `failed` for review chain agents. Non-blocking warnings that accumulate and surface at human gates. Relevant if binary pass/fail proves too coarse during agent testing — specifically if the review chain keeps flagging minor issues that shouldn't block but shouldn't be invisible.

**Evolution Engine** — Background process for pattern extraction, drift detection, fitness-based re-evolution, and security sentinel. Relevant post-MVP when the codebase is large enough that patterns emerge and drift matters.