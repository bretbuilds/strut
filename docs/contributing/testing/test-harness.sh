#!/bin/bash
# test-harness.sh — Shared test harness for STRUT skills and agents.
#
# Sourced by generated test scripts at .strut-pipeline/test-<component>.sh.
# Provides agent dispatch (invoke_agent), fixture setup (setup_clean),
# assertion helpers (assert_*), result reporting (print_results,
# save_results), and cleanup.
#
# Contract for sourcing scripts:
#   - Must set COMPONENT=<component-name> before calling any function that
#     uses it (setup_clean, save_results, print_results, cleanup).
#   - Must set LAST_OUTPUT=<file-path> before calling invoke_agent.
#
# Usage from a generated test script:
#   source docs/contributing/testing/test-harness.sh
#   COMPONENT="spec-write"
#
#   setup_clean
#   LAST_OUTPUT=".strut-pipeline/test-case-1-output.txt"
#   invoke_agent "$COMPONENT"
#   assert_file_exists .strut-pipeline/spec-refinement/spec.json "Case 1"
#   ...
#   print_results
#   save_results
#   cleanup

PASS=0
FAIL=0
RESULTS=""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ── Logging ──────────────────────────────────────────────────────────────────

log_pass() {
  PASS=$((PASS + 1))
  RESULTS="${RESULTS}\n${GREEN}✅ PASS${NC}: $1"
}

log_fail() {
  FAIL=$((FAIL + 1))
  RESULTS="${RESULTS}\n${RED}❌ FAIL${NC}: $1 — $2"
}

log_info() {
  echo -e "${YELLOW}▸${NC} $1"
}

# ── Fixture setup ────────────────────────────────────────────────────────────

# Scratch paths the harness should also scrub between tests. Use when the
# component under test writes files outside .strut-pipeline/ (e.g., impl-write-tests
# writes actual test files into the project's source tree). Cleanup is git-aware
# — tracked files are left alone; only untracked and ignored files are removed.
# Test scripts register paths with register_scratch_path before running tests.
SCRATCH_PATHS=()
register_scratch_path() {
  SCRATCH_PATHS+=("$1")
}

# Clean slate before each test. Preserves the test script itself. Removes
# untracked files under any registered scratch paths so one test's artifacts
# cannot be reused by a later test.
setup_clean() {
  find .strut-pipeline -mindepth 1 -not -name "test-${COMPONENT}.sh" -delete 2>/dev/null
  local scratch_msg=""
  if [ ${#SCRATCH_PATHS[@]} -gt 0 ] && command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
    for path in "${SCRATCH_PATHS[@]}"; do
      if [ -e "$path" ]; then
        git clean -fdx -- "$path" >/dev/null 2>&1
      fi
    done
    scratch_msg=" and scratch paths (${SCRATCH_PATHS[*]})"
  fi
  log_info "Cleaned .strut-pipeline/${scratch_msg}"
}

# ── Component dispatch ───────────────────────────────────────────────────────
# Single source of truth for how components (agents and skills) are invoked in
# tests. Generated test scripts MUST use this function, not define their own.
#
# Usage:
#   LAST_OUTPUT=".strut-pipeline/my-test-output.txt"
#   invoke_agent <component-name>              # default prompt "run"
#   invoke_agent <component-name> "<prompt>"   # custom prompt
#
# Auto-detects component kind:
#   - If .claude/skills/<name>/SKILL.md exists → dispatch via slash command
#     (claude -p "/<name> <prompt>"). Skills cannot be invoked via --agent.
#   - Else if .claude/agents/<name>.md exists → dispatch via claude -p --agent.
#   - Else → log failure and return 1.
#
# Output (stdout+stderr) is captured to $LAST_OUTPUT for downstream assertions.
# Kept named `invoke_agent` for backward compatibility with prior generated
# scripts that predate skill auto-detection.

invoke_agent() {
  local name="$1"
  local prompt="${2:-run}"

  if [ -z "${LAST_OUTPUT:-}" ]; then
    log_fail "invoke_agent(${name})" "LAST_OUTPUT not set — test script must set it before calling invoke_agent"
    return 1
  fi

  if [ -f ".claude/skills/${name}/SKILL.md" ]; then
    # Skill — dispatch via slash command. Prompt is appended after the skill name.
    claude -p "/${name} ${prompt}" \
      --dangerously-skip-permissions \
      < /dev/null \
      2>&1 | tee "$LAST_OUTPUT"
  elif [ -f ".claude/agents/${name}.md" ]; then
    # Agent — dispatch via --agent.
    claude -p "$prompt" \
      --agent "$name" \
      --dangerously-skip-permissions \
      2>&1 | tee "$LAST_OUTPUT"
  else
    log_fail "invoke_agent(${name})" "no component file found at .claude/skills/${name}/SKILL.md or .claude/agents/${name}.md"
    return 1
  fi
}

# Alias for clarity in new test scripts where the component is explicitly a skill.
invoke_skill() { invoke_agent "$@"; }

# ── Assertions ───────────────────────────────────────────────────────────────

# Verify a file exists
assert_file_exists() {
  if [ -f "$1" ]; then
    log_pass "$2: file exists ($1)"
  else
    log_fail "$2: file missing ($1)" "expected file not created"
  fi
}

# Verify a file does NOT exist
assert_file_not_exists() {
  if [ ! -f "$1" ]; then
    log_pass "$2: file correctly absent ($1)"
  else
    log_fail "$2: file should not exist ($1)" "boundary violation"
  fi
}

# Verify JSON is valid
assert_valid_json() {
  if python3 -c "import json; json.load(open('$1'))" 2>/dev/null; then
    log_pass "$2: valid JSON ($1)"
  else
    log_fail "$2: invalid JSON ($1)" "file is not parseable JSON"
  fi
}

# Verify a JSON field has an expected value
assert_json_field() {
  local file="$1" field="$2" expected="$3" label="$4"
  local actual
  actual=$(python3 -c "import json; print(json.load(open('$file')).get('$field', 'MISSING'))" 2>/dev/null)
  if [ "$actual" = "$expected" ]; then
    log_pass "$label: $field = $expected"
  else
    log_fail "$label: $field expected '$expected' got '$actual'" "wrong field value"
  fi
}

# Verify a JSON field is one of several allowed values
assert_json_field_oneof() {
  local file="$1" field="$2" label="$3"
  shift 3
  local allowed=("$@")
  local actual
  actual=$(python3 -c "import json; print(json.load(open('$file')).get('$field', 'MISSING'))" 2>/dev/null)
  for val in "${allowed[@]}"; do
    if [ "$actual" = "$val" ]; then
      log_pass "$label: $field = $actual (allowed)"
      return
    fi
  done
  log_fail "$label: $field = $actual not in allowed values [${allowed[*]}]" "unexpected status"
}

# Verify a file contains specific text
assert_file_contains() {
  if grep -q "$2" "$1" 2>/dev/null; then
    log_pass "$3: file contains '$2'"
  else
    log_fail "$3: file missing expected content '$2'" "in $1"
  fi
}

# Verify a file does NOT contain specific text
assert_file_not_contains() {
  if ! grep -q "$2" "$1" 2>/dev/null; then
    log_pass "$3: file correctly omits '$2'"
  else
    log_fail "$3: file contains prohibited content '$2'" "boundary violation in $1"
  fi
}

# ── Results reporting ────────────────────────────────────────────────────────

# Save results to docs/contributing/testing/results/
save_results() {
  local results_dir="docs/contributing/testing/results"
  mkdir -p "$results_dir"
  local results_file="${results_dir}/test-${COMPONENT}-$(date -u +%Y%m%d-%H%M%S).txt"
  {
    echo "Component: ${COMPONENT}"
    echo "Model: [opus|sonnet]"
    echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Pass: ${PASS}"
    echo "Fail: ${FAIL}"
    echo ""
    echo -e "$RESULTS"
  } > "$results_file"
  log_info "Results saved to ${results_file}"
}

# Print results
print_results() {
  echo ""
  echo "════════════════════════════════════════"
  echo -e " ${COMPONENT} Test Results ($(date -u +%H:%M:%S))"
  echo "════════════════════════════════════════"
  echo -e "$RESULTS"
  echo ""
  echo "════════════════════════════════════════"
  echo -e " Total: $((PASS + FAIL)) | ${GREEN}Pass: ${PASS}${NC} | ${RED}Fail: ${FAIL}${NC}"
  echo "════════════════════════════════════════"

  if [ $FAIL -gt 0 ]; then
    echo -e "\n${RED}COMPONENT NOT READY — failures require investigation${NC}"
    echo -e "Test artifacts preserved in .strut-pipeline/ for debugging"
  else
    echo -e "\n${GREEN}ALL TESTS PASSED${NC}"
  fi
}

# Cleanup test artifacts
# Only runs on all-pass. Preserves artifacts on failure for debugging.
cleanup() {
  if [ $FAIL -eq 0 ]; then
    log_info "All tests passed — cleaning fixture files (preserving test script)"
    find .strut-pipeline -mindepth 1 -not -name "test-${COMPONENT}.sh" -delete 2>/dev/null
    if [ ${#SCRATCH_PATHS[@]} -gt 0 ] && command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
      for path in "${SCRATCH_PATHS[@]}"; do
        if [ -e "$path" ]; then
          git clean -fdx -- "$path" >/dev/null 2>&1
        fi
      done
    fi
    echo -e "${GREEN}Fixture artifacts cleaned up${NC}"
  else
    log_info "Failures detected — preserving test artifacts for debugging"
    log_info "Fixture files and results in .strut-pipeline/"
    log_info "Test script at .strut-pipeline/test-${COMPONENT}.sh"
    echo ""
    echo "After fixing the component in a separate session, re-run:"
    echo "  bash docs/contributing/testing/run-tests.sh ${COMPONENT}"
  fi

  # Propagate failure count as exit status so callers can detect failures.
  # Cap at 1 because exit codes >125 collide with shell-reserved values.
  if [ $FAIL -gt 0 ]; then
    exit 1
  fi
}