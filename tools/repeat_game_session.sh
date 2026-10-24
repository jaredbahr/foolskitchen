#!/usr/bin/env bash
# Same-process predecessor diagnostics, never retries. Default/--prefix runs
# the normal sorted file prefix through game_session; --full runs every file.
# --baseline preserves the original 30 filtered samples as an explicit option.
# Run after a strict import. All logs are retained and printed in full.
set +e
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root" || exit 2
ver="$(tr -d '[:space:]' < tools/godot_version.txt)"
GODOT="${GODOT:-.tools/godot-$ver/Godot_v${ver}-stable_linux.x86_64}"
mode="${1:---prefix}"
phase=PREFIX
runs=20
args=(--diagnose-game-session --through-game-session)
case "$mode" in
  --prefix) ;;
  --full) phase=FULL; args=(--diagnose-game-session) ;;
  --baseline) phase=BASELINE; runs=30; args=(--filter=game_session) ;;
  *) echo 'Usage: bash tools/repeat_game_session.sh [--prefix|--full|--baseline]'; exit 2 ;;
esac
if (($# > 1)); then
  echo 'Usage: bash tools/repeat_game_session.sh [--prefix|--full|--baseline]'
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
if [[ "$phase" == BASELINE ]]; then
  printf '%s\n' "$target" >"$expected"
else
  if ! git ls-files 'tests/**/test_*.gd' 'tests/test_*.gd' | LC_ALL=C sort -u \
      | awk -v target="$target" -v mode="$phase" '{ path="res://" $0; if (mode=="FULL" || !seen) print path; if (path==target) seen=1 } END { if (!seen) exit 1 }' >"$expected"; then
    echo "$phase INCOMPLETE: cannot establish the tracked ordered test selection."
    echo "$phase SUMMARY: requested=$runs attempted=0 passed=0 failed=0 incomplete=$runs"
    exit 2
  fi
fi
expected_files="$(wc -l <"$expected")"
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
  planned="$log_dir/run-$label-plan.txt"
  : >"$actual"
  : >"$planned"
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
  summaries=0; test_passed=0; test_failed=0; completions=0
  completed_files=0; completed_methods=0; target_methods=0; diagnostics=0
  while IFS= read -r line; do
    if [[ "$line" == 'TEST FILE: '* ]]; then
      printf '%s\n' "${line#TEST FILE: }" >>"$actual"
    elif [[ "$line" == 'DIAG SELECTED: '* ]]; then
      printf '%s\n' "${line#DIAG SELECTED: }" >>"$planned"
    elif [[ "$line" =~ ^TESTS:\ ([0-9]+)\ passed,\ ([0-9]+)\ failed$ ]]; then
      summaries=$((summaries + 1)); test_passed="${BASH_REMATCH[1]}"; test_failed="${BASH_REMATCH[2]}"
    elif [[ "$line" =~ ^DIAG\ COMPLETE:\ files=([0-9]+)\ methods=([0-9]+)\ target_methods=([0-9]+)$ ]]; then
      completions=$((completions + 1)); completed_files="${BASH_REMATCH[1]}"
      completed_methods="${BASH_REMATCH[2]}"; target_methods="${BASH_REMATCH[3]}"
    elif [[ "$line" == 'SAVE DIAG: '* ]]; then
      diagnostics=$((diagnostics + 1))
    fi
  done <"$log"
  total=$((test_passed + test_failed))
  selection_ok=1
  cmp -s "$expected" "$actual" || selection_ok=0
  if [[ "$phase" != BASELINE ]]; then
    cmp -s "$expected" "$planned" || selection_ok=0
    ((completions == 1 && completed_files == expected_files && completed_methods == total \
      && target_methods == 8 && diagnostics == 24)) || selection_ok=0
  else
    ((total == 8)) || selection_ok=0
  fi
  if [[ "$code" == not-started || "$code" == 124 || "$code" == 137 ]] \
      || ((summaries != 1 || selection_ok != 1)); then
    status=incomplete; incomplete=$((incomplete + 1))
  elif [[ "$code" != 0 ]] || ((test_failed > 0)) \
      || grep -Eq '^FAIL[[:space:]]|SCRIPT ERROR|Parse Error|^[[:space:]]*ERROR:' "$log"; then
    status=failed; failed=$((failed + 1))
  else
    status=passed; passed=$((passed + 1))
  fi
  echo "$phase RUN: sample=$label/$runs status=$status exit=$code selected_files=$expected_files tests=$total passed=$test_passed failed=$test_failed target_methods=$target_methods snapshots=$diagnostics"
done
echo "$phase SUMMARY: requested=$runs attempted=$attempted passed=$passed failed=$failed incomplete=$incomplete"
echo "$phase FAILURE LINES (complete logs and pre-teardown snapshots are above):"
grep -H -E '^FAIL[[:space:]]|SCRIPT ERROR|Parse Error|^[[:space:]]*ERROR:|^INCOMPLETE:' "$log_dir"/run-*.log || true
if ((failed == 0 && incomplete == 0 && passed == runs)); then
  echo "$phase RESULT: not reproduced in $runs/$runs complete runs; no cause or post-fix acceptance is established."
  exit 0
fi
echo "$phase RESULT: $failed/$runs failed, $incomplete/$runs incomplete; no sample was retried."
exit 1
