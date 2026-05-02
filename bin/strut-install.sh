#!/usr/bin/env bash
# strut-install.sh — Deterministic installer for STRUT pipeline files.
# Copies templates to .claude/, merges settings, appends CLAUDE.md block.
# Called by /strut:init skill. Does not fill TODO placeholders (Claude handles that).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPLATES="${PLUGIN_ROOT}/templates"
TARGET_DIR="$(pwd)"

# Allow override via environment (for testing)
CLAUDE_DIR="${TARGET_DIR}/.claude"
MANIFEST="${TARGET_DIR}/strut-manifest.json"

echo "STRUT installer: target=${TARGET_DIR}"

# --- Step 1: Create directories ---
mkdir -p "${CLAUDE_DIR}/skills"
mkdir -p "${CLAUDE_DIR}/agents"
mkdir -p "${CLAUDE_DIR}/rules"
mkdir -p "${CLAUDE_DIR}/scripts"
mkdir -p "${TARGET_DIR}/.strut-pipeline"
mkdir -p "${TARGET_DIR}/.strut-specs"
touch "${TARGET_DIR}/.strut-specs/.gitkeep"
echo "  [✓] Directories created"

# --- Step 2: Copy skills ---
SKILLS_COPIED=0
for skill_dir in "${TEMPLATES}/skills"/*/; do
  if [ -d "$skill_dir" ]; then
    skill_name="$(basename "$skill_dir")"
    cp -r "$skill_dir" "${CLAUDE_DIR}/skills/${skill_name}"
    SKILLS_COPIED=$((SKILLS_COPIED + 1))
  fi
done
echo "  [✓] ${SKILLS_COPIED} skills copied"

# --- Step 3: Copy agents ---
AGENTS_COPIED=0
for agent_file in "${TEMPLATES}/agents"/*.md; do
  if [ -f "$agent_file" ]; then
    cp "$agent_file" "${CLAUDE_DIR}/agents/"
    AGENTS_COPIED=$((AGENTS_COPIED + 1))
  fi
done
echo "  [✓] ${AGENTS_COPIED} agents copied"

# --- Step 4: Copy rules templates ---
RULES_COPIED=0
for rule_file in "${TEMPLATES}/rules"/*.md; do
  if [ -f "$rule_file" ]; then
    cp "$rule_file" "${CLAUDE_DIR}/rules/"
    RULES_COPIED=$((RULES_COPIED + 1))
  fi
done
echo "  [✓] ${RULES_COPIED} rules templates copied"

# --- Step 5: Copy scripts ---
SCRIPTS_COPIED=0
for script_file in "${TEMPLATES}/scripts"/*.sh; do
  if [ -f "$script_file" ]; then
    cp "$script_file" "${CLAUDE_DIR}/scripts/"
    chmod +x "${CLAUDE_DIR}/scripts/$(basename "$script_file")"
    SCRIPTS_COPIED=$((SCRIPTS_COPIED + 1))
  fi
done
echo "  [✓] ${SCRIPTS_COPIED} scripts copied"

# --- Step 6: Merge settings.json ---
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
FRAGMENT="${TEMPLATES}/settings-fragment.json"

if [ -f "$SETTINGS_FILE" ]; then
  # Deep merge: deduplicate permission arrays, recursive merge hooks
  MERGED=$(jq --slurpfile frag "$FRAGMENT" '
    . as $existing | $frag[0] as $new | {
      permissions: {
        deny: (($existing.permissions.deny // []) + ($new.permissions.deny // []) | unique),
        ask: (($existing.permissions.ask // []) + ($new.permissions.ask // []) | unique),
        allow: (($existing.permissions.allow // []) + ($new.permissions.allow // []) | unique)
      },
      hooks: (($existing.hooks // {}) * ($new.hooks // {}))
    }
  ' "$SETTINGS_FILE")
  echo "$MERGED" > "$SETTINGS_FILE"
  echo "  [✓] settings.json merged (existing + STRUT permissions)"
else
  cp "$FRAGMENT" "$SETTINGS_FILE"
  echo "  [✓] settings.json created"
fi

# --- Step 7: Append CLAUDE.md block ---
CLAUDE_MD="${TARGET_DIR}/CLAUDE.md"
BLOCK_FILE="${TEMPLATES}/claude-md-block.md"

if [ -f "$CLAUDE_MD" ]; then
  if grep -q "STRUT:BEGIN" "$CLAUDE_MD"; then
    echo "  [—] CLAUDE.md already has STRUT block, skipping"
  else
    echo "" >> "$CLAUDE_MD"
    cat "$BLOCK_FILE" >> "$CLAUDE_MD"
    echo "  [✓] STRUT block appended to CLAUDE.md"
  fi
else
  cat "$BLOCK_FILE" > "$CLAUDE_MD"
  echo "  [✓] CLAUDE.md created with STRUT block"
fi

# --- Step 8: Write manifest ---
INSTALLED_FILES=$(find "${CLAUDE_DIR}/skills" "${CLAUDE_DIR}/agents" "${CLAUDE_DIR}/rules" "${CLAUDE_DIR}/scripts" -type f | sort | jq -R . | jq -s .)

cat > "$MANIFEST" << EOF
{
  "version": "1.0.0",
  "installed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "plugin_source": "${PLUGIN_ROOT}",
  "files": ${INSTALLED_FILES}
}
EOF
echo "  [✓] strut-manifest.json written"

# --- Step 9: Configure .gitignore for STRUT working state and OS metadata ---
GITIGNORE="${TARGET_DIR}/.gitignore"
[ -f "$GITIGNORE" ] || touch "$GITIGNORE"

# Append a section header + patterns only if any pattern is missing. Avoids
# duplicate headers on re-run while keeping the file readable.
ensure_section() {
  local header="$1"
  shift
  local missing=0
  for pattern in "$@"; do
    if ! grep -qxF "$pattern" "$GITIGNORE"; then
      missing=1
      break
    fi
  done
  if [ "$missing" -eq 0 ]; then
    return
  fi
  printf "\n%s\n" "$header" >> "$GITIGNORE"
  for pattern in "$@"; do
    if ! grep -qxF "$pattern" "$GITIGNORE"; then
      echo "$pattern" >> "$GITIGNORE"
      echo "  [✓] ${pattern} added to .gitignore"
    fi
  done
}

ensure_section "# STRUT pipeline working state" ".strut-pipeline/"
ensure_section "# OS metadata"                  ".DS_Store" "Thumbs.db"

# --- Step 10: Untrack .DS_Store if it's already tracked ---
# A repo with .DS_Store committed before init defeats the new ignore line —
# git only ignores untracked files. Untrack every .DS_Store path now so the
# next commit removes them from the tree.
if [ -d "${TARGET_DIR}/.git" ]; then
  TRACKED_DS=$(git -C "$TARGET_DIR" ls-files | grep -E '(^|/)\.DS_Store$' || true)
  if [ -n "$TRACKED_DS" ]; then
    DS_COUNT=$(printf '%s\n' "$TRACKED_DS" | wc -l | tr -d ' ')
    printf '%s\n' "$TRACKED_DS" | xargs -I {} git -C "$TARGET_DIR" rm --cached --quiet "{}"
    echo "  [✓] Untracked ${DS_COUNT} .DS_Store file(s) — commit to finalize"
  fi
fi

echo ""
echo "STRUT install complete. ${SKILLS_COPIED} skills, ${AGENTS_COPIED} agents, ${RULES_COPIED} rules, ${SCRIPTS_COPIED} scripts."
echo ""
echo "Next: Claude will analyze your project and fill TODO placeholders in rules files."
