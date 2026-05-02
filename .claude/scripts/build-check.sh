#!/usr/bin/env bash
# build-check.sh — Detects the project toolchain, runs build → lint → typecheck
# → test, and writes the result to .strut-pipeline/build-check/build-check.json.
#
# Override: if .strut/build.json exists, its commands take absolute priority
# over auto-detection. Each of its four fields (build, lint, typecheck, test)
# is either a shell-command string or null (skip).
#
# Auto-detect order (first marker wins): Node.js (package.json) → Rust
# (Cargo.toml) → Go (go.mod) → Python (pyproject.toml) → Makefile.
#
# Not fail-fast: every defined check runs, so build-error-cleanup has the full
# picture. Exit 0 on overall passed, 1 on overall failed (including detection
# failure).
#
# This is a bash script, not an agent. No LLM calls, no network.

set -u

PIPELINE_DIR=".strut-pipeline/build-check"
OUTPUT_FILE="${PIPELINE_DIR}/build-check.json"
OVERRIDE_CONFIG=".strut/build.json"
MAX_OUTPUT_LINES=100

mkdir -p "$PIPELINE_DIR"
rm -f "$OUTPUT_FILE"

STAGE_DIR=$(mktemp -d)
trap 'rm -rf "$STAGE_DIR"' EXIT

TOOLCHAIN=""

# Plan variables — set by detectors, consumed by execute_plan.
cmd_build=""
cmd_lint=""
cmd_typecheck=""
cmd_test=""
skip_build=""
skip_lint=""
skip_typecheck=""
skip_test=""

get_cmd() {
  case "$1" in
    build)     printf '%s' "$cmd_build" ;;
    lint)      printf '%s' "$cmd_lint" ;;
    typecheck) printf '%s' "$cmd_typecheck" ;;
    test)      printf '%s' "$cmd_test" ;;
  esac
}

get_skip() {
  case "$1" in
    build)     printf '%s' "$skip_build" ;;
    lint)      printf '%s' "$skip_lint" ;;
    typecheck) printf '%s' "$skip_typecheck" ;;
    test)      printf '%s' "$skip_test" ;;
  esac
}

set_cmd() {
  case "$1" in
    build)     cmd_build="$2" ;;
    lint)      cmd_lint="$2" ;;
    typecheck) cmd_typecheck="$2" ;;
    test)      cmd_test="$2" ;;
  esac
}

set_skip() {
  case "$1" in
    build)     skip_build="$2" ;;
    lint)      skip_lint="$2" ;;
    typecheck) skip_typecheck="$2" ;;
    test)      skip_test="$2" ;;
  esac
}

# ─── Result recording helpers ───────────────────────────────────────────────

record_skipped() {
  local stage="$1" reason="$2"
  printf 'skipped' > "$STAGE_DIR/$stage.status"
  printf '%s' "$reason" > "$STAGE_DIR/$stage.reason"
}

record_passed() {
  local stage="$1" cmd="$2" duration="$3"
  printf 'passed' > "$STAGE_DIR/$stage.status"
  printf '%s' "$cmd" > "$STAGE_DIR/$stage.command"
  printf '%s' "$duration" > "$STAGE_DIR/$stage.duration"
}

record_failed() {
  local stage="$1" cmd="$2" duration="$3" output_file="$4"
  printf 'failed' > "$STAGE_DIR/$stage.status"
  printf '%s' "$cmd" > "$STAGE_DIR/$stage.command"
  printf '%s' "$duration" > "$STAGE_DIR/$stage.duration"
  tail -n "$MAX_OUTPUT_LINES" "$output_file" > "$STAGE_DIR/$stage.output"
}

run_stage() {
  local stage="$1" cmd="$2"
  local out_file start end duration code
  out_file=$(mktemp)
  start=$(date +%s)
  bash -c "$cmd" > "$out_file" 2>&1
  code=$?
  end=$(date +%s)
  duration=$((end - start))
  if [ $code -eq 0 ]; then
    record_passed "$stage" "$cmd" "$duration"
  else
    record_failed "$stage" "$cmd" "$duration" "$out_file"
  fi
  rm -f "$out_file"
}

# ─── Detectors ──────────────────────────────────────────────────────────────

# Returns 0 if detection matched (with cmd_*/skip_* populated), 1 otherwise.
detect_override() {
  [ -f "$OVERRIDE_CONFIG" ] || return 1
  TOOLCHAIN="override"
  if ! python3 -c "import json; json.load(open('$OVERRIDE_CONFIG'))" 2>/dev/null; then
    for s in build lint typecheck test; do
      set_skip "$s" "malformed .strut/build.json"
    done
    return 0
  fi
  local v
  for s in build lint typecheck test; do
    v=$(python3 - "$OVERRIDE_CONFIG" "$s" <<'PY' 2>/dev/null
import json, sys
with open(sys.argv[1]) as f:
    cfg = json.load(f)
key = sys.argv[2]
if key not in cfg:
    print("__MISSING__")
else:
    val = cfg[key]
    if val is None:
        print("__NULL__")
    else:
        print(val)
PY
)
    if [ "$v" = "__NULL__" ]; then
      set_skip "$s" "null in .strut/build.json"
    elif [ "$v" = "__MISSING__" ]; then
      set_skip "$s" "not defined in .strut/build.json"
    else
      set_cmd "$s" "$v"
    fi
  done
  return 0
}

has_pkg_script() {
  python3 - "$1" <<'PY' 2>/dev/null
import json, sys
try:
    with open("package.json") as f:
        pkg = json.load(f)
except Exception:
    sys.exit(1)
sys.exit(0 if (pkg.get("scripts") or {}).get(sys.argv[1]) else 1)
PY
}

detect_node() {
  [ -f package.json ] || return 1
  local pm="npm"
  if   [ -f pnpm-lock.yaml ]; then pm="pnpm"
  elif [ -f yarn.lock ];      then pm="yarn"
  elif [ -f bun.lockb ];      then pm="bun"
  fi
  TOOLCHAIN="node-$pm"
  for s in build lint typecheck test; do
    if has_pkg_script "$s"; then
      set_cmd "$s" "$pm run $s"
    else
      set_skip "$s" "no \"$s\" script in package.json"
    fi
  done
  return 0
}

detect_rust() {
  [ -f Cargo.toml ] || return 1
  TOOLCHAIN="rust"
  set_cmd  "build"     "cargo build"
  set_cmd  "lint"      "cargo clippy -- -D warnings"
  set_skip "typecheck" "compiler handles type checking during build"
  set_cmd  "test"      "cargo test"
  return 0
}

detect_go() {
  [ -f go.mod ] || return 1
  TOOLCHAIN="go"
  set_cmd "build" "go build ./..."
  if command -v golangci-lint >/dev/null 2>&1; then
    set_cmd "lint" "golangci-lint run"
  else
    set_skip "lint" "golangci-lint not installed"
  fi
  set_cmd "typecheck" "go vet ./..."
  set_cmd "test"      "go test ./..."
  return 0
}

detect_python() {
  [ -f pyproject.toml ] || return 1
  TOOLCHAIN="python"
  set_skip "build" "not applicable for Python projects"
  if command -v ruff >/dev/null 2>&1; then
    set_cmd "lint" "ruff check ."
  elif command -v flake8 >/dev/null 2>&1; then
    set_cmd "lint" "flake8"
  else
    set_skip "lint" "no ruff or flake8 installed"
  fi
  if command -v mypy >/dev/null 2>&1; then
    set_cmd "typecheck" "mypy ."
  else
    set_skip "typecheck" "mypy not installed"
  fi
  if command -v pytest >/dev/null 2>&1; then
    set_cmd "test" "pytest"
  else
    set_cmd "test" "python -m unittest discover"
  fi
  return 0
}

has_make_target() {
  make -n "$1" >/dev/null 2>&1
}

detect_makefile() {
  [ -f Makefile ] || return 1
  TOOLCHAIN="makefile"
  for s in build lint typecheck test; do
    if has_make_target "$s"; then
      set_cmd "$s" "make $s"
    else
      set_skip "$s" "no \"$s\" target in Makefile"
    fi
  done
  return 0
}

# ─── Execution and output ───────────────────────────────────────────────────

execute_plan() {
  local stage cmd skip
  for stage in build lint typecheck test; do
    cmd=$(get_cmd "$stage")
    skip=$(get_skip "$stage")
    if [ -n "$skip" ]; then
      record_skipped "$stage" "$skip"
    elif [ -n "$cmd" ]; then
      run_stage "$stage" "$cmd"
    else
      record_skipped "$stage" "no command resolved"
    fi
  done
}

emit_result() {
  TOOLCHAIN="$TOOLCHAIN" STAGE_DIR="$STAGE_DIR" OUTPUT_FILE="$OUTPUT_FILE" \
  python3 - <<'PY'
import json, os
stage_dir = os.environ["STAGE_DIR"]
toolchain = os.environ["TOOLCHAIN"]
output_file = os.environ["OUTPUT_FILE"]

def read(name, default=""):
    p = os.path.join(stage_dir, name)
    if not os.path.exists(p):
        return default
    with open(p) as f:
        return f.read()

def read_int(name, default=0):
    v = read(name)
    try:    return int(v)
    except: return default

stages = ["build", "lint", "typecheck", "test"]
checks = {}
failed = []
for s in stages:
    status = read(f"{s}.status")
    if status == "skipped":
        checks[s] = {"status": "skipped", "reason": read(f"{s}.reason")}
    elif status == "passed":
        checks[s] = {
            "status": "passed",
            "command": read(f"{s}.command"),
            "duration_seconds": read_int(f"{s}.duration"),
        }
    elif status == "failed":
        checks[s] = {
            "status": "failed",
            "command": read(f"{s}.command"),
            "duration_seconds": read_int(f"{s}.duration"),
            "error_output": read(f"{s}.output"),
        }
        failed.append(s)
    else:
        checks[s] = {"status": "skipped", "reason": "not evaluated"}

overall = "failed" if failed else "passed"
if failed:
    plural = "s" if len(failed) != 1 else ""
    summary = f"{len(failed)} check{plural} failed: {', '.join(failed)}."
else:
    summary = "All checks passed."

result = {
    "skill": "build-check",
    "status": overall,
    "toolchain": toolchain,
    "checks": checks,
    "summary": summary,
}
with open(output_file, "w") as f:
    json.dump(result, f, indent=2)
    f.write("\n")
PY
}

emit_detection_failure() {
  OUTPUT_FILE="$OUTPUT_FILE" python3 - <<'PY'
import json, os
result = {
    "skill": "build-check",
    "status": "failed",
    "toolchain": None,
    "checks": {
        "build":     {"status": "skipped", "reason": "no toolchain detected"},
        "lint":      {"status": "skipped", "reason": "no toolchain detected"},
        "typecheck": {"status": "skipped", "reason": "no toolchain detected"},
        "test":      {"status": "skipped", "reason": "no toolchain detected"},
    },
    "summary": (
        "Could not detect build toolchain. Create .strut/build.json with your "
        "build, lint, typecheck, and test commands."
    ),
}
with open(os.environ["OUTPUT_FILE"], "w") as f:
    json.dump(result, f, indent=2)
    f.write("\n")
PY
}

# ─── Main flow ──────────────────────────────────────────────────────────────

if   detect_override; then execute_plan
elif detect_node;     then execute_plan
elif detect_rust;     then execute_plan
elif detect_go;       then execute_plan
elif detect_python;   then execute_plan
elif detect_makefile; then execute_plan
else
  emit_detection_failure
  exit 1
fi

emit_result

overall=$(python3 -c "import json; print(json.load(open('$OUTPUT_FILE'))['status'])")
if [ "$overall" = "passed" ]; then
  exit 0
else
  exit 1
fi
