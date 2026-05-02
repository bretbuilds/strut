#!/usr/bin/env bash
# test-build-check.sh — Exercises .claude/scripts/build-check.sh across fixture
# projects. Creates a temp dir per test case, runs the script inside it, asserts
# the result JSON and exit code. No state leaks back to the STRUT repo.

set -u

SCRIPT_ABS="$(cd "$(dirname "$0")" && pwd)/build-check.sh"
if [ ! -x "$SCRIPT_ABS" ]; then
  echo "FATAL: $SCRIPT_ABS not executable" >&2
  exit 2
fi

PASS=0
FAIL=0
FAIL_NAMES=()

record() {
  local name="$1" ok="$2" detail="${3:-}"
  if [ "$ok" = "1" ]; then
    PASS=$((PASS+1))
    printf '  ✓ %s\n' "$name"
  else
    FAIL=$((FAIL+1))
    FAIL_NAMES+=("$name")
    printf '  ✗ %s\n' "$name"
    [ -n "$detail" ] && printf '      %s\n' "$detail"
  fi
}

json_field() {
  python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(eval('d'+sys.argv[2]))" "$1" "$2" 2>/dev/null
}

json_valid() {
  python3 -c "import json,sys;json.load(open(sys.argv[1]))" "$1" 2>/dev/null
}

write_override() {
  mkdir -p .strut
  printf '%s' "$1" > .strut/build.json
}

write_pkg() {
  printf '%s' "$1" > package.json
}

run_case() {
  local name="$1"
  shift
  local fixture_dir orig_dir
  fixture_dir=$(mktemp -d)
  orig_dir=$(pwd)
  cd "$fixture_dir" || return 2
  "$@"
  local code=$?
  cd "$orig_dir" || return 2
  rm -rf "$fixture_dir"
  return $code
}

OUT=".strut-pipeline/build-check/build-check.json"

# ─── T1: No markers, no override → detection failure, exit 1 ────────────────
t1() {
  set +e; "$SCRIPT_ABS" >/dev/null; local code=$?; set -e
  [ "$code" = "1" ] && record "T1 exit 1" 1 || record "T1 exit 1" 0 "got $code"
  json_valid "$OUT" && record "T1 valid JSON" 1 || record "T1 valid JSON" 0
  local status tc summary
  status=$(json_field "$OUT" "['status']")
  tc=$(json_field "$OUT" "['toolchain']")
  summary=$(json_field "$OUT" "['summary']")
  [ "$status" = "failed" ] && record "T1 status=failed" 1 || record "T1 status=failed" 0 "got '$status'"
  [ "$tc" = "None" ] && record "T1 toolchain=null" 1 || record "T1 toolchain=null" 0 "got '$tc'"
  case "$summary" in
    *"Could not detect"*".strut/build.json"*) record "T1 helpful summary" 1 ;;
    *) record "T1 helpful summary" 0 "got: $summary" ;;
  esac
  for s in build lint typecheck test; do
    local cs
    cs=$(json_field "$OUT" "['checks']['$s']['status']")
    [ "$cs" = "skipped" ] && record "T1 $s skipped" 1 || record "T1 $s skipped" 0 "got '$cs'"
  done
}

# ─── T2: Override, all "true" commands → status passed, exit 0 ──────────────
t2() {
  write_override '{"build":"true","lint":"true","typecheck":"true","test":"true"}'
  set +e; "$SCRIPT_ABS" >/dev/null; local code=$?; set -e
  [ "$code" = "0" ] && record "T2 exit 0" 1 || record "T2 exit 0" 0 "got $code"
  local tc status
  tc=$(json_field "$OUT" "['toolchain']")
  status=$(json_field "$OUT" "['status']")
  [ "$tc" = "override" ] && record "T2 toolchain=override" 1 || record "T2 toolchain=override" 0 "got '$tc'"
  [ "$status" = "passed" ] && record "T2 status=passed" 1 || record "T2 status=passed" 0 "got '$status'"
  for s in build lint typecheck test; do
    local cs cmd
    cs=$(json_field "$OUT" "['checks']['$s']['status']")
    cmd=$(json_field "$OUT" "['checks']['$s']['command']")
    [ "$cs" = "passed" ] && record "T2 $s passed" 1 || record "T2 $s passed" 0 "got '$cs'"
    [ "$cmd" = "true" ] && record "T2 $s command=true" 1 || record "T2 $s command=true" 0 "got '$cmd'"
  done
  local summary
  summary=$(json_field "$OUT" "['summary']")
  [ "$summary" = "All checks passed." ] && record "T2 summary ok" 1 || record "T2 summary ok" 0 "got '$summary'"
}

# ─── T3: Override, build fails → other stages still run, exit 1, output captured ──
t3() {
  write_override '{"build":"echo BUILD_BROKE 1>&2; exit 3","lint":"true","typecheck":"true","test":"true"}'
  set +e; "$SCRIPT_ABS" >/dev/null; local code=$?; set -e
  [ "$code" = "1" ] && record "T3 exit 1" 1 || record "T3 exit 1" 0 "got $code"
  local status bstatus boutput summary
  status=$(json_field "$OUT" "['status']")
  bstatus=$(json_field "$OUT" "['checks']['build']['status']")
  boutput=$(json_field "$OUT" "['checks']['build']['error_output']")
  summary=$(json_field "$OUT" "['summary']")
  [ "$status" = "failed" ] && record "T3 status=failed" 1 || record "T3 status=failed" 0 "got '$status'"
  [ "$bstatus" = "failed" ] && record "T3 build.status=failed" 1 || record "T3 build.status=failed" 0 "got '$bstatus'"
  case "$boutput" in
    *BUILD_BROKE*) record "T3 error_output captured" 1 ;;
    *) record "T3 error_output captured" 0 "got: $boutput" ;;
  esac
  # Other stages must have run (not fail-fast)
  for s in lint typecheck test; do
    local cs
    cs=$(json_field "$OUT" "['checks']['$s']['status']")
    [ "$cs" = "passed" ] && record "T3 $s still ran (passed)" 1 || record "T3 $s still ran" 0 "got '$cs'"
  done
  case "$summary" in
    *"1 check failed: build"*) record "T3 summary names failure" 1 ;;
    *) record "T3 summary names failure" 0 "got: $summary" ;;
  esac
}

# ─── T4: Override with null → that stage skipped with reason ────────────────
t4() {
  write_override '{"build":"true","lint":null,"typecheck":"true","test":"true"}'
  set +e; "$SCRIPT_ABS" >/dev/null; local code=$?; set -e
  [ "$code" = "0" ] && record "T4 exit 0" 1 || record "T4 exit 0" 0 "got $code"
  local lstatus lreason
  lstatus=$(json_field "$OUT" "['checks']['lint']['status']")
  lreason=$(json_field "$OUT" "['checks']['lint']['reason']")
  [ "$lstatus" = "skipped" ] && record "T4 lint skipped" 1 || record "T4 lint skipped" 0 "got '$lstatus'"
  case "$lreason" in *null*) record "T4 lint reason mentions null" 1 ;; *) record "T4 lint reason mentions null" 0 "got: $lreason" ;; esac
}

# ─── T5: Override with missing key → stage skipped ──────────────────────────
t5() {
  write_override '{"build":"true","typecheck":"true","test":"true"}'
  set +e; "$SCRIPT_ABS" >/dev/null; local code=$?; set -e
  local lstatus lreason
  lstatus=$(json_field "$OUT" "['checks']['lint']['status']")
  lreason=$(json_field "$OUT" "['checks']['lint']['reason']")
  [ "$lstatus" = "skipped" ] && record "T5 missing key skipped" 1 || record "T5 missing key skipped" 0 "got '$lstatus'"
  case "$lreason" in *"not defined"*) record "T5 missing-key reason" 1 ;; *) record "T5 missing-key reason" 0 "got: $lreason" ;; esac
}

# ─── T6: Malformed override JSON → all stages skipped with reason ───────────
t6() {
  write_override '{this is not valid json'
  set +e; "$SCRIPT_ABS" >/dev/null; local code=$?; set -e
  local status tc
  tc=$(json_field "$OUT" "['toolchain']")
  status=$(json_field "$OUT" "['status']")
  [ "$tc" = "override" ] && record "T6 toolchain=override" 1 || record "T6 toolchain=override" 0 "got '$tc'"
  # Overall status should be passed (all skipped, none failed)
  [ "$status" = "passed" ] && record "T6 all skipped → passed" 1 || record "T6 all skipped → passed" 0 "got '$status'"
  for s in build lint typecheck test; do
    local cs reason
    cs=$(json_field "$OUT" "['checks']['$s']['status']")
    reason=$(json_field "$OUT" "['checks']['$s']['reason']")
    [ "$cs" = "skipped" ] && record "T6 $s skipped" 1 || record "T6 $s skipped" 0 "got '$cs'"
    case "$reason" in *malformed*) record "T6 $s reason=malformed" 1 ;; *) record "T6 $s reason=malformed" 0 "got: $reason" ;; esac
  done
}

# ─── T7: Node detection (npm) with all 4 scripts ────────────────────────────
t7() {
  write_pkg '{"name":"x","scripts":{"build":"true","lint":"true","typecheck":"true","test":"true"}}'
  set +e; "$SCRIPT_ABS" >/dev/null; local code=$?; set -e
  [ "$code" = "0" ] && record "T7 exit 0" 1 || record "T7 exit 0" 0 "got $code"
  local tc
  tc=$(json_field "$OUT" "['toolchain']")
  [ "$tc" = "node-npm" ] && record "T7 toolchain=node-npm" 1 || record "T7 toolchain=node-npm" 0 "got '$tc'"
  for s in build lint typecheck test; do
    local cs cmd
    cs=$(json_field "$OUT" "['checks']['$s']['status']")
    cmd=$(json_field "$OUT" "['checks']['$s']['command']")
    [ "$cs" = "passed" ] && record "T7 $s passed" 1 || record "T7 $s passed" 0 "got '$cs'"
    [ "$cmd" = "npm run $s" ] && record "T7 $s uses npm" 1 || record "T7 $s uses npm" 0 "got '$cmd'"
  done
}

# ─── T8: Node detection with pnpm-lock.yaml → toolchain=node-pnpm ───────────
t8() {
  write_pkg '{"name":"x","scripts":{"build":"true"}}'
  touch pnpm-lock.yaml
  set +e; "$SCRIPT_ABS" >/dev/null; set -e
  local tc cmd
  tc=$(json_field "$OUT" "['toolchain']")
  cmd=$(json_field "$OUT" "['checks']['build']['command']")
  [ "$tc" = "node-pnpm" ] && record "T8 toolchain=node-pnpm" 1 || record "T8 toolchain=node-pnpm" 0 "got '$tc'"
  [ "$cmd" = "pnpm run build" ] && record "T8 command uses pnpm" 1 || record "T8 command uses pnpm" 0 "got '$cmd'"
}

# ─── T9: Node detection with partial scripts → missing ones skipped ─────────
t9() {
  write_pkg '{"name":"x","scripts":{"build":"true","test":"true"}}'
  "$SCRIPT_ABS" >/dev/null
  for s in build test; do
    local cs
    cs=$(json_field "$OUT" "['checks']['$s']['status']")
    [ "$cs" = "passed" ] && record "T9 $s passed" 1 || record "T9 $s passed" 0 "got '$cs'"
  done
  for s in lint typecheck; do
    local cs reason
    cs=$(json_field "$OUT" "['checks']['$s']['status']")
    reason=$(json_field "$OUT" "['checks']['$s']['reason']")
    [ "$cs" = "skipped" ] && record "T9 $s skipped" 1 || record "T9 $s skipped" 0 "got '$cs'"
    case "$reason" in *"no \"$s\" script"*) record "T9 $s reason names script" 1 ;; *) record "T9 $s reason names script" 0 "got: $reason" ;; esac
  done
}

# ─── T10: Makefile detection with some targets ──────────────────────────────
t10() {
  cat > Makefile <<'EOF'
build:
	@true
test:
	@true
EOF
  set +e; "$SCRIPT_ABS" >/dev/null; local code=$?; set -e
  [ "$code" = "0" ] && record "T10 exit 0" 1 || record "T10 exit 0" 0 "got $code"
  local tc
  tc=$(json_field "$OUT" "['toolchain']")
  [ "$tc" = "makefile" ] && record "T10 toolchain=makefile" 1 || record "T10 toolchain=makefile" 0 "got '$tc'"
  local bcmd bstat
  bstat=$(json_field "$OUT" "['checks']['build']['status']")
  bcmd=$(json_field "$OUT" "['checks']['build']['command']")
  [ "$bstat" = "passed" ] && record "T10 build passed" 1 || record "T10 build passed" 0 "got '$bstat'"
  [ "$bcmd" = "make build" ] && record "T10 build cmd=make build" 1 || record "T10 build cmd=make build" 0 "got '$bcmd'"
  # lint and typecheck have no targets → skipped
  for s in lint typecheck; do
    local cs
    cs=$(json_field "$OUT" "['checks']['$s']['status']")
    [ "$cs" = "skipped" ] && record "T10 $s skipped (no target)" 1 || record "T10 $s skipped" 0 "got '$cs'"
  done
}

# ─── T11: Override takes priority over auto-detect ──────────────────────────
t11() {
  write_pkg '{"name":"x","scripts":{"build":"echo FROM_NPM"}}'
  write_override '{"build":"echo FROM_OVERRIDE","lint":null,"typecheck":null,"test":null}'
  "$SCRIPT_ABS" >/dev/null
  local tc cmd
  tc=$(json_field "$OUT" "['toolchain']")
  cmd=$(json_field "$OUT" "['checks']['build']['command']")
  [ "$tc" = "override" ] && record "T11 toolchain=override" 1 || record "T11 toolchain=override" 0 "got '$tc'"
  [ "$cmd" = "echo FROM_OVERRIDE" ] && record "T11 override wins over npm" 1 || record "T11 override wins over npm" 0 "got '$cmd'"
}

# ─── T12: Error output truncation to last 100 lines ────────────────────────
t12() {
  local cmd
  # Emit 200 lines then fail; last lines should be preserved
  cmd='for i in $(seq 1 200); do echo "LINE_$i"; done; exit 1'
  write_override "$(printf '{"build":%s,"lint":null,"typecheck":null,"test":null}' "$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$cmd")")"
  "$SCRIPT_ABS" >/dev/null || true
  local out
  out=$(python3 -c "import json; print(json.load(open('$OUT'))['checks']['build']['error_output'])")
  local line_count
  line_count=$(printf '%s' "$out" | grep -c '^LINE_' || true)
  # Should be at most 100
  [ "$line_count" -le 100 ] && record "T12 truncated to ≤100 lines" 1 || record "T12 truncated ≤100" 0 "got $line_count lines"
  # Last line (LINE_200) must be preserved
  case "$out" in *LINE_200*) record "T12 preserves tail (LINE_200)" 1 ;; *) record "T12 preserves tail" 0 "tail not found" ;; esac
  # First line (LINE_1) should be absent (truncated from head)
  case "$out" in *"LINE_1"$'\n'*|*"LINE_1"$) record "T12 drops head (LINE_1 absent)" 0 "LINE_1 still present" ;; *) record "T12 drops head (LINE_1 absent)" 1 ;; esac
}

# ─── T13: Stale output overwritten ──────────────────────────────────────────
t13() {
  mkdir -p .strut-pipeline/build-check
  echo '{"skill":"build-check","status":"STALE_SENTINEL"}' > "$OUT"
  write_override '{"build":"true","lint":"true","typecheck":"true","test":"true"}'
  "$SCRIPT_ABS" >/dev/null
  json_valid "$OUT" && record "T13 valid JSON (not appended)" 1 || record "T13 valid JSON" 0
  ! grep -q STALE_SENTINEL "$OUT" && record "T13 stale content gone" 1 || record "T13 stale content gone" 0
}

# ─── T14: Schema compliance — required fields per architecture ──────────────
t14() {
  write_override '{"build":"true","lint":"echo X 1>&2; exit 1","typecheck":null,"test":"true"}'
  "$SCRIPT_ABS" >/dev/null || true
  python3 <<PY && record "T14 top-level schema" 1 || record "T14 top-level schema" 0
import json
d = json.load(open("$OUT"))
assert d["skill"] == "build-check"
assert d["status"] in ("passed", "failed")
assert "toolchain" in d
assert "checks" in d
assert "summary" in d
for s in ("build","lint","typecheck","test"):
    assert s in d["checks"]
PY
  python3 <<PY && record "T14 passed check shape" 1 || record "T14 passed check shape" 0
import json
c = json.load(open("$OUT"))["checks"]["build"]
assert c["status"] == "passed"
assert "command" in c and "duration_seconds" in c
assert isinstance(c["duration_seconds"], int)
PY
  python3 <<PY && record "T14 failed check shape" 1 || record "T14 failed check shape" 0
import json
c = json.load(open("$OUT"))["checks"]["lint"]
assert c["status"] == "failed"
assert "command" in c and "duration_seconds" in c and "error_output" in c
PY
  python3 <<PY && record "T14 skipped check shape" 1 || record "T14 skipped check shape" 0
import json
c = json.load(open("$OUT"))["checks"]["typecheck"]
assert c["status"] == "skipped"
assert "reason" in c and c["reason"]
PY
}

# ─── T15: Node detection with yarn-lock ─────────────────────────────────────
t15() {
  write_pkg '{"name":"x","scripts":{"build":"true"}}'
  touch yarn.lock
  "$SCRIPT_ABS" >/dev/null || true
  local tc cmd
  tc=$(json_field "$OUT" "['toolchain']")
  cmd=$(json_field "$OUT" "['checks']['build']['command']")
  [ "$tc" = "node-yarn" ] && record "T15 toolchain=node-yarn" 1 || record "T15 toolchain=node-yarn" 0 "got '$tc'"
  [ "$cmd" = "yarn run build" ] && record "T15 cmd uses yarn" 1 || record "T15 cmd uses yarn" 0 "got '$cmd'"
}

echo "Running .claude/scripts/build-check.sh test suite..."
echo

echo "T1 (no markers, no override → detection failure):";            run_case T1 t1;  echo
echo "T2 (override all 'true' → passed):";                           run_case T2 t2;  echo
echo "T3 (override, build fails → not fail-fast, output captured):"; run_case T3 t3;  echo
echo "T4 (override null → skipped):";                                run_case T4 t4;  echo
echo "T5 (override missing key → skipped):";                         run_case T5 t5;  echo
echo "T6 (malformed override → all skipped):";                       run_case T6 t6;  echo
echo "T7 (node-npm detection, all scripts):";                        run_case T7 t7;  echo
echo "T8 (node-pnpm detection via pnpm-lock):";                      run_case T8 t8;  echo
echo "T9 (node partial scripts → missing skipped):";                 run_case T9 t9;  echo
echo "T10 (makefile detection, partial targets):";                   run_case T10 t10; echo
echo "T11 (override beats auto-detect):";                            run_case T11 t11; echo
echo "T12 (error output truncated to last 100 lines):";              run_case T12 t12; echo
echo "T13 (stale output overwritten):";                              run_case T13 t13; echo
echo "T14 (schema compliance):";                                     run_case T14 t14; echo
echo "T15 (node-yarn detection via yarn.lock):";                     run_case T15 t15; echo

echo "========================================"
echo " Pass: $PASS"
echo " Fail: $FAIL"
echo "========================================"
if [ "$FAIL" -gt 0 ]; then
  echo "Failed: ${FAIL_NAMES[*]}"
  exit 1
fi
exit 0
