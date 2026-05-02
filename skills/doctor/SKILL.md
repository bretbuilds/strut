---
description: Check STRUT installation health — constraint count, file integrity, and configuration issues.
---

# strut:doctor

Run health checks on the STRUT installation.

## Checks

### 1. Manifest integrity

Read `strut-manifest.json`. For each file listed, verify it exists. Report missing files.

### 2. Constraint count

Count constraints (numbered rules) across `CLAUDE.md` and `.claude/rules/*.md`, separating **always-loaded** rules from **scoped** rules. A rules file with `globs:` frontmatter is scoped — it only loads when Claude works in matching paths, so it doesn't compete for attention every session.

For each rules file:
- If frontmatter has no `globs:` field → constraints count toward **always-loaded** total.
- If frontmatter has `globs:` → constraints count under that file's scope, listed separately.

Constraints in `CLAUDE.md` are always loaded.

Report shape:

```
Always loaded:                X constraints   (compares against 50 ceiling)
Scoped to <pattern-1>:        Y constraints   (loads only in matching paths)
Scoped to <pattern-2>:        Z constraints
...
Total across all files:       N constraints   (informational)
```

Apply the Curse of Instructions threshold to the **always-loaded** number only. The expected compliance rate uses `success_all = 0.99^N` where N is always-loaded:

| Always-loaded count | Expected full compliance |
|---------------------|------------------------|
| 20 | 82% |
| 30 | 74% |
| 40 | 67% |
| 50 | 61% |
| 60 | 55% |
| 70 | 50% |

If always-loaded exceeds 50, suggest:
- Consolidating overlapping rules within unscoped files
- Moving rules from unscoped files into scoped files where the rule only applies in specific paths
- Removing rules that restate what architecture already enforces

Scoped files are reported for visibility but do not trigger the warning.

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
