---
description: Initialize STRUT in the current project. Copies pipeline files, merges settings, and uses AI to fill project-specific placeholders.
---

# strut:init

Initialize the STRUT development pipeline in this project.

## What this does

1. Runs the install script (deterministic file copy + merge)
2. Analyzes the project to fill TODO placeholders in rules files
3. Runs a health check on total constraint count

## Execution

### Step 1: Run the install script

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/strut-install.sh"
```

Run this script. It first verifies git preconditions (the project is a git repo, has at least one commit on the current branch, and the working tree is clean), then copies skills, agents, rules, and scripts to `.claude/`, merges permissions into settings.json, appends the STRUT block to CLAUDE.md, and writes strut-manifest.json.

If the script fails, report the error and stop. Common preflight failures and how to relay them:

- **Not a git repo** — tell the user to `git init`, stage files, and make an initial commit before re-running `/strut:init`.
- **Zero commits** — tell the user to `git add .` and `git commit -m "initial commit"` before re-running.
- **Dirty tree** — show them the `git status` output the script printed, and ask whether they want to commit, stash, or discard before re-running.

Do not attempt to fix the precondition silently on the user's behalf (don't auto-commit, don't auto-stash). The user should decide what to do with their working tree.

### Step 2: Analyze the project and fill placeholders

After the script completes, read the project to detect:

1. **Build commands** — look for package.json scripts, Makefile, Cargo.toml, pyproject.toml, go.mod, or equivalent. Fill in the `<!-- A1: -->` placeholder in CLAUDE.md and update `.claude/scripts/build-check.sh` with the actual commands.

2. **Directory structure** — read the top-level layout and update `.claude/rules/strut-architecture.md` rule 1's directory tree to match reality. Update rule 2 (shared logic location) if the project doesn't use `app/lib/` and `app/components/`.

3. **Language-specific conventions** — detect the primary language and fill the `<!-- A7: -->` TODO in `.claude/rules/strut-operating-rules.md` with appropriate conventions.

4. **Data layer** — if you can confidently detect the project's data-layer path conventions (e.g., the project clearly uses Postgres with migrations under `db/migrations/`), update the `globs:` frontmatter in `.claude/rules/strut-database.md` to match those paths. Otherwise, **leave the file alone**. The shipped globs target SQL/multi-tenant patterns; if the project doesn't match, the file stays dormant (globs don't match → file doesn't load) and is available unchanged for the user to adapt later if their project grows a data layer.

   Anti-pattern: do NOT remove the `globs:` frontmatter. That promotes the file from scoped to always-loaded, which is the opposite of the intent.

5. **Stack-specific permissions** — detect the build/test/lint toolchain and add appropriate entries to the `allow` list in `.claude/settings.json` (e.g., `Bash(pytest:*)` for Python, `Bash(cargo test:*)` for Rust).

6. **Dependency manifest protection** — identify manifest files (package.json, Cargo.toml, go.mod, etc.) and add them to the `ask` list in `.claude/settings.json`.

7. **Gitignore** — uncomment the stack-specific block in `.gitignore` if one matches, or add standard ignores for the detected language.

### Step 3: Report what was filled and what needs human input

After filling placeholders, report:

- What was detected and filled (with confidence level)
- Any rules files left as shipped because the project doesn't currently match (e.g., `strut-database.md` left untouched on a no-data-layer project — the file is dormant via its globs and will activate if matching paths appear later)
- What could NOT be auto-detected and needs the user's input:
  - MUST NEVER constraints (`.claude/rules/strut-security.md` — requires domain knowledge)
  - Business context (`docs/user-context/` — optional but recommended)
  - Any rules that looked wrong for the detected stack

### Step 4: Run doctor check

Invoke the same constraint-count logic that `/strut:doctor` uses: count constraints (numbered rules) in `CLAUDE.md` and each `.claude/rules/*.md` file, splitting **always-loaded** rules (no `globs:` frontmatter) from **scoped** rules (those with `globs:`). Apply the Curse of Instructions threshold to the *always-loaded* count only — that is what loads every session and competes for attention. Scoped rules are reported separately and do not trigger the warning.

If always-loaded exceeds 50, warn and suggest consolidation strategies (consolidate overlapping rules, move single-context rules into a scoped file, remove rules that restate what architecture already enforces). If a NOT APPLICABLE rules file was deleted in Step 2, the deleted file's constraints have already been excluded from the count — no separate adjustment needed.

## Important

- Do NOT skip the install script. It guarantees every file is copied.
- Do NOT modify files the script hasn't created (user's existing code, their rules files, their CLAUDE.md content above the STRUT block).
- Do NOT delete shipped rules files. A rules file whose globs don't match the current project is dormant (not loaded), not broken — it's ready to activate the moment matching paths exist. Leave it alone.
- Flag uncertainty rather than guessing. "I detected X but I'm not confident" is better than silently writing wrong rules.
