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

Run this script. It copies skills, agents, rules, and scripts to `.claude/`, merges permissions into settings.json, appends the STRUT block to CLAUDE.md, and writes strut-manifest.json.

If the script fails, report the error and stop.

### Step 2: Analyze the project and fill placeholders

After the script completes, read the project to detect:

1. **Build commands** — look for package.json scripts, Makefile, Cargo.toml, pyproject.toml, go.mod, or equivalent. Fill in the `<!-- A1: -->` placeholder in CLAUDE.md and update `.claude/scripts/build-check.sh` with the actual commands.

2. **Directory structure** — read the top-level layout and update `.claude/rules/strut-architecture.md` rule 1's directory tree to match reality. Update rule 2 (shared logic location) if the project doesn't use `app/lib/` and `app/components/`.

3. **Language-specific conventions** — detect the primary language and fill the `<!-- A7: -->` TODO in `.claude/rules/strut-operating-rules.md` with appropriate conventions.

4. **Data layer** — check if the project uses SQL/Postgres/multi-tenant patterns. If yes, uncomment the `globs:` frontmatter in `.claude/rules/strut-database.md` and set paths. If the project uses a different data layer (NoSQL, single-tenant, etc.), flag this for the user to review rather than silently adapting.

5. **Stack-specific permissions** — detect the build/test/lint toolchain and add appropriate entries to the `allow` list in `.claude/settings.json` (e.g., `Bash(pytest:*)` for Python, `Bash(cargo test:*)` for Rust).

6. **Dependency manifest protection** — identify manifest files (package.json, Cargo.toml, go.mod, etc.) and add them to the `ask` list in `.claude/settings.json`.

7. **Gitignore** — uncomment the stack-specific block in `.gitignore` if one matches, or add standard ignores for the detected language.

### Step 3: Report what was filled and what needs human input

After filling placeholders, report:

- What was detected and filled (with confidence level)
- What could NOT be auto-detected and needs the user's input:
  - MUST NEVER constraints (`.claude/rules/strut-security.md` — requires domain knowledge)
  - Business context (`docs/user-context/` — optional but recommended)
  - Any rules that looked wrong for the detected stack

### Step 4: Run doctor check

Count total constraints across CLAUDE.md and all `.claude/rules/*.md` files. Report the count and its implications per the Curse of Instructions research. If combined with the user's existing rules the count exceeds 50, warn and suggest consolidation strategies.

## Important

- Do NOT skip the install script. It guarantees every file is copied.
- Do NOT modify files the script hasn't created (user's existing code, their rules files, their CLAUDE.md content above the STRUT block).
- Flag uncertainty rather than guessing. "I detected X but I'm not confident" is better than silently writing wrong rules.
