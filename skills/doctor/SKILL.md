---
description: Check STRUT installation health — constraint count, file integrity, and configuration issues.
---

# strut:doctor

Run health checks on the STRUT installation.

## Checks

### 1. Manifest integrity

Read `strut-manifest.json`. For each file listed, verify it exists. Report missing files.

### 2. Constraint count

Count total constraints (numbered rules) across:
- `CLAUDE.md`
- All files in `.claude/rules/*.md`

Report the count and the expected compliance rate using the Curse of Instructions formula: `success_all = 0.99^N`.

| Count | Expected full compliance |
|-------|------------------------|
| 20 | 82% |
| 30 | 74% |
| 40 | 67% |
| 50 | 61% |
| 60 | 55% |
| 70 | 50% |

If count exceeds 50, suggest:
- Consolidating overlapping rules
- Removing rules that restate what architecture already enforces
- Using `globs:` scoping to reduce always-loaded rules

### 3. Scoping verification

For each rules file with `globs:` frontmatter, verify the glob patterns match actual project paths. Report globs that would never match anything.

### 4. Settings completeness

Check `.claude/settings.json` for:
- At least one deny entry (security baseline)
- At least one allow entry for build commands
- PreToolUse hooks present (mechanical enforcement)

Report gaps.

### 5. Pipeline directories

Verify `.strut-pipeline/` and `.strut-specs/` exist. Check `.gitignore` includes `.strut-pipeline/`.

## Output

Present results as a checklist with pass/warn/fail status for each check. For any warn or fail, include a one-line fix suggestion.
