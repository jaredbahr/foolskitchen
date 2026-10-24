#!/usr/bin/env bash
# Manual filtered verification, never retries. Default/--verify requests 50
# consecutive processes; --baseline preserves the original 30-sample option.
# Run by hand after a strict import, never from CI. All logs are retained.
set +e
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root" || exit 2
ver="$(tr -d '[:space:]' < tools/godot_version.txt)"
GODOT="${GODOT:-.tools/godot-$ver/Godot_v${ver}-stable_linux.x86_64}"
mode="${1:---verify}"
phase=VERIFY
runs=50
args=(--filter=game_session)
case "$mode" in
  --verify) ;;
  --baseline) phase=BASELINE; runs=30 ;;
  *) echo 'Usage: bash tools/repeat_game_session.sh [--verify|--baseline]'; exit 2 ;;
esac
if (($# > 1)); then
  echo 'Usage: bash tools/repeat_game_session.sh [--verify|--baseline]'
  exit 2
fi
target="res://tests/world/test_game_session.gd"
per_run_seconds=20
kill_grace_seconds=2
batch_seconds=300
if [[ ! -x "$GODOT" ]] || ! command -v timeout >/dev/null; then
  echo "$phase INCOMPLETE: imported pinned Godot and timeout are required."
  echo "$phase SUMMARY: requested=$runs attempted=0 passed=0 failed=0 incomplete=$runs"
  exit 2
fi
if ! log_dir="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/foolskitchen-game-session-${phase,,}.XXXXXX")"; then
  echo "$phase SUMMARY: requested=$runs attempted=0 passed=0 failed=0 incomplete=$runs"
  exit 2
fi
expected="$log_dir/expected-files.txt"
printf '%s\n' "$target" >"$expected"
expected_files=1
echo "$phase: samples=$runs selected_files=$expected_files target=$target logs=$log_dir"
cat "$expected"
echo "$phase LIMITS: per_process=${per_run_seconds}s batch=${batch_seconds}s kill_grace=${kill_grace_seconds}s"
deadline=$((SECONDS + batch_seconds))
attempted=0
passed=0
failed=0
incomplete=0
for ((index=1; index<=runs; index++)); do
  printf -v label '%02d' "$index"
  log="$log_dir/run-$label.log"
  actual="$log_dir/run-$label-files.txt"
  : >"$actual"
  remaining=$((deadline - SECONDS - kill_grace_seconds))
  duration=$per_run_seconds
  ((duration > remaining)) && duration=$remaining
  code=not-started
  if ((duration > 0)); then
    attempted=$((attempted + 1))
    timeout --kill-after="${kill_grace_seconds}s" "${duration}s" "$GODOT" \
      --headless --path . --script tools/run_tests.gd -- "${args[@]}" >"$log" 2>&1
    code=$?
  else
    printf 'INCOMPLETE: batch budget exhausted before sample %s; no process started.\n' "$label" >"$log"
  fi
  echo "$phase LOG BEGIN: sample=$label exit=$code file=$log"
  cat "$log"
  echo "$phase LOG END: sample=$label"
  summaries=0; test_passed=0; test_failed=0
  while IFS= read -r line; do
    if [[ "$line" == 'TEST FILE: '* ]]; then
      printf '%s\n' "${line#TEST FILE: }" >>"$actual"
    elif [[ "$line" =~ ^TESTS:\ ([0-9]+)\ passed,\ ([0-9]+)\ failed$ ]]; then
      summaries=$((summaries + 1)); test_passed="${BASH_REMATCH[1]}"; test_failed="${BASH_REMATCH[2]}"
    fi
  done <"$log"
  total=$((test_passed + test_failed))
  selection_ok=1
  cmp -s "$expected" "$actual" || selection_ok=0
  ((total == 8)) || selection_ok=0
  if [[ "$code" == not-started || "$code" == 124 || "$code" == 137 ]] \
      || ((summaries != 1 || selection_ok != 1)); then
    status=incomplete; incomplete=$((incomplete + 1))
  elif [[ "$code" != 0 ]] || ((test_failed > 0)) \
      || grep -Eq '^FAIL[[:space:]]|SCRIPT ERROR|Parse Error|^[[:space:]]*ERROR:' "$log"; then
    status=failed; failed=$((failed + 1))
  else
    status=passed; passed=$((passed + 1))
  fi
  echo "$phase RUN: sample=$label/$runs status=$status exit=$code selected_files=$expected_files tests=$total passed=$test_passed failed=$test_failed"
done
echo "$phase SUMMARY: requested=$runs attempted=$attempted passed=$passed failed=$failed incomplete=$incomplete"
echo "$phase FAILURE LINES (complete logs are above):"
grep -H -E '^FAIL[[:space:]]|SCRIPT ERROR|Parse Error|^[[:space:]]*ERROR:|^INCOMPLETE:' "$log_dir"/run-*.log || true
if ((failed == 0 && incomplete == 0 && passed == runs)); then
  echo "$phase RESULT: all $runs consecutive filtered runs passed."
  exit 0
fi
echo "$phase RESULT: $failed/$runs failed, $incomplete/$runs incomplete; no sample was retried."
exit 1
