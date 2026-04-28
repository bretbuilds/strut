# docs/contributing/testing/

Testing workflow for STRUT skills and agents. One command generates and runs tests under both Claude models, catching model-specific failures that only appear in one.

## The workflow

After authoring a skill or agent, run:

```bash
bash docs/contributing/testing/run-tests.sh <component-name>
```

where `<component-name>` is either a skill (matches `.claude/skills/<name>/SKILL.md`) or an agent (matches `.claude/agents/<name>.md`).

The script:

1. Locates the component file (skill or agent).
2. If no test script exists at `.pipeline/test-<component>.sh`, invokes Claude to generate one using `test-categories.md` as the guide and `test-harness.sh` as the assertion library.
3. Runs the test script under Sonnet.
4. Runs the test script under Opus.
5. Saves per-model transcripts to `results/` (gitignored).
6. Prints a side-by-side pass/fail comparison.

A component is considered ready when all applicable categories pass on both models.

## Files in this folder

**`run-tests.sh`** — the single entry point. Generation + dual-model execution + reporting.

**`test-harness.sh`** — bash assertion library sourced by generated test scripts. Provides `assert_file_exists`, `assert_json_field`, `assert_file_contains`, etc. The harness also handles cleanup (preserves artifacts on failure, cleans fixtures on all-pass).

**`test-categories.md`** — the seven test categories (A–G) generated scripts should cover. A is happy path, B is failure handling, C is boundary constraints, D is anti-rationalization, E is pipeline handoff, F is model-specific regression, G is domain-specific edge cases.

## Where test artifacts go

- **Generated test scripts:** `.pipeline/test-<component>.sh` (ephemeral, lives inside `.pipeline/`)
- **Test transcripts:** `docs/contributing/testing/results/` (gitignored, persistent for local debugging)
- **Generation logs:** `docs/contributing/testing/results/generate-<component>-<timestamp>.txt`

## When things go wrong

If a run fails, the harness preserves fixture files in `.pipeline/` and keeps the test script at `.pipeline/test-<component>.sh`. You can re-run the script directly without regenerating:

```bash
bash .pipeline/test-<component>.sh
```

If the test script itself is wrong (generated incorrectly), delete it and re-run `run-tests.sh` — it will regenerate.

## Dependencies

- Claude Code CLI (`claude`) on PATH
- `python3` for JSON parsing in the harness
- `jq` for optional post-run inspection of result files
- Standard bash 4+
