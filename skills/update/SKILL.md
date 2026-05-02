---
description: Update STRUT pipeline files to the latest version while preserving project-specific customizations in rules and settings.
---

# strut:update

Update the STRUT pipeline machinery to the latest plugin version.

## What this does

1. Reads strut-manifest.json to identify STRUT-owned files
2. Updates pipeline skills, agents, and scripts (overwrite — these are not customized)
3. Preserves rules files (user has customized these)
4. Reports what changed

## Execution

### Step 1: Verify manifest exists

Read `strut-manifest.json` in the project root. If it doesn't exist, tell the user to run `/strut:init` first and stop.

### Step 2: Update pipeline machinery

Run the following to refresh skills, agents, and scripts:

```bash
cp -r "${CLAUDE_PLUGIN_ROOT}/templates/skills/"* .claude/skills/
cp -r "${CLAUDE_PLUGIN_ROOT}/templates/agents/"* .claude/agents/
cp -r "${CLAUDE_PLUGIN_ROOT}/templates/scripts/"* .claude/scripts/
```

These are pipeline machinery — not project-specific. Safe to overwrite.

### Step 3: Check rules for upstream changes

For each file in `${CLAUDE_PLUGIN_ROOT}/templates/rules/`:
- Diff it against the user's `.claude/rules/` version
- If the template added NEW rules that don't exist in the user's copy, report them
- Do NOT overwrite — rules files contain user customizations

Present any new upstream rules as suggestions the user can manually add.

### Step 4: Update manifest

Update strut-manifest.json with the new version and timestamp.

### Step 5: Report

- List files updated (skills, agents, scripts)
- List new rules available upstream (if any)
- Note the new version number

## Important

- NEVER overwrite rules files. They contain project-specific customizations.
- NEVER modify settings.json during update (user may have added their own permissions).
- If a skill was renamed or removed upstream, note it but don't delete the old copy without confirmation.
