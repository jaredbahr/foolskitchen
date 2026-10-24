#!/usr/bin/env bash
# Diagnostic baseline only: 30 independent filtered processes, never retries.
# Run after a successful headless import. Logs survive in the runner temp dir
# and every complete log is also printed into the retained Actions job output.
set +e
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root" || exit 2
ver="$(tr -d '[:space:]' < tools/godot_version.txt)"
GODOT="${GODOT:-.tools/godot-$ver/Godot_v${ver}-stable_linux.x86_64}"
runs=30
expected_path="res://tests/world/test_game_session.gd"
expected_tests=8
per_run_seconds=20
kill_grace_seconds=2
batch_seconds=300

if [[ ! -x "$GODOT" ]] || ! command -v timeout >/dev/null; then
  echo 'BASELINE INCOMPLETE: imported pinned Godot and timeout are required; no samples ran.'
  echo "BASELINE SUMMARY: requested=$runs attempted=0 passed=0 failed=0 incomplete=$runs"
  exit 2
fi
if ! log_dir="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/foolskitchen-game-session-baseline.XXXXXX")"; then
  echo 'BASELINE INCOMPLETE: cannot create a log directory; no samples ran.'
  echo "BASELINE SUMMARY: requested=$runs attempted=0 passed=0 failed=0 incomplete=$runs"
  exit 2
fi
echo "BASELINE: filter=game_session expected_path=$expected_path expected_tests=$expected_tests logs=$log_dir"
echo "BASELINE LIMITS: per_process=${per_run_seconds}s batch=${batch_seconds}s kill_grace=${kill_grace_seconds}s"
deadline=$((SECONDS + batch_seconds))
attempted=0
passed=0
failed=0
incomplete=0

for ((index=1; index<=runs; index++)); do
  printf -v label '%02d' "$index"
  log="$log_dir/run-$label.log"
  remaining=$((deadline - SECONDS - kill_grace_seconds))
  code=not-started
  if ((remaining > 0)); then
    duration=$per_run_seconds
    ((duration > remaining)) && duration=$remaining
    attempted=$((attempted + 1))
    timeout --kill-after="${kill_grace_seconds}s" "${duration}s" "$GODOT" \
      --headless --path . --script tools/run_tests.gd -- --filter=game_session >"$log" 2>&1
    code=$?
  else
    printf 'INCOMPLETE: batch time budget exhausted before sample %s; no process started.\n' "$label" >"$log"
  fi
  echo "BASELINE LOG BEGIN: sample=$label exit=$code file=$log"
  cat "$log"
  echo "BASELINE LOG END: sample=$label"

  selections=0
  selected_path=""
  summaries=0
  test_passed=0
  test_failed=0
  while IFS= read -r line; do
    if [[ "$line" == 'TEST FILE: '* ]]; then
      selections=$((selections + 1))
      selected_path="${line#TEST FILE: }"
    elif [[ "$line" =~ ^TESTS:\ ([0-9]+)\ passed,\ ([0-9]+)\ failed$ ]]; then
      summaries=$((summaries + 1))
      test_passed="${BASH_REMATCH[1]}"
      test_failed="${BASH_REMATCH[2]}"
    fi
  done <"$log"
  total=$((test_passed + test_failed))
  if [[ "$code" == not-started || "$code" == 124 || "$code" == 137 ]] \
      || ((selections != 1 || summaries != 1 || total != expected_tests)) \
      || [[ "$selected_path" != "$expected_path" ]]; then
    status=incomplete
    incomplete=$((incomplete + 1))
  elif [[ "$code" != 0 ]] || ((test_failed > 0)) \
      || grep -Eq '^FAIL[[:space:]]|SCRIPT ERROR|Parse Error|^[[:space:]]*ERROR:' "$log"; then
    status=failed
    failed=$((failed + 1))
  else
    status=passed
    passed=$((passed + 1))
  fi
  echo "BASELINE RUN: sample=$label/$runs status=$status exit=$code selected_files=$selections path=$selected_path tests=$total passed=$test_passed failed=$test_failed"
done

echo "BASELINE SUMMARY: requested=$runs attempted=$attempted passed=$passed failed=$failed incomplete=$incomplete"
echo 'BASELINE FAILURE LINES (complete logs are above):'
grep -H -E '^FAIL[[:space:]]|SCRIPT ERROR|Parse Error|^[[:space:]]*ERROR:|^INCOMPLETE:' "$log_dir"/run-*.log || true
if ((failed == 0 && incomplete == 0 && passed == runs)); then
  echo "BASELINE RESULT: not reproduced in $runs/$runs filtered runs; this does not establish a root cause."
  exit 0
fi
echo "BASELINE RESULT: $failed/$runs failed runs, $incomplete/$runs incomplete; no failed sample was retried."
exit 1
