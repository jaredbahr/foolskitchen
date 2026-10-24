#!/usr/bin/env bash
# Diagnostic samples, never retries: --baseline (default) runs 30 sequential
# processes; --overlap runs five pairs with at most two headless processes.
# Run after a successful headless import. Logs survive in the runner temp dir
# and every complete log is also printed into the retained Actions job output.
set +e
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root" || exit 2
ver="$(tr -d '[:space:]' < tools/godot_version.txt)"
GODOT="${GODOT:-.tools/godot-$ver/Godot_v${ver}-stable_linux.x86_64}"
phase=BASELINE
runs=30
workers=1
case "${1:---baseline}" in
  --baseline) ;;
  --overlap) phase=OVERLAP; runs=10; workers=2 ;;
  *) echo 'Usage: bash tools/repeat_game_session.sh [--baseline|--overlap]'; exit 2 ;;
esac
if (($# > 1)); then
  echo 'Usage: bash tools/repeat_game_session.sh [--baseline|--overlap]'
  exit 2
fi
expected_path="res://tests/world/test_game_session.gd"
expected_tests=8
per_run_seconds=20
kill_grace_seconds=2
batch_seconds=300

if [[ ! -x "$GODOT" ]] || ! command -v timeout >/dev/null; then
  echo "$phase INCOMPLETE: imported pinned Godot and timeout are required; no samples ran."
  echo "$phase SUMMARY: requested=$runs attempted=0 passed=0 failed=0 incomplete=$runs"
  exit 2
fi
if ! log_dir="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/foolskitchen-game-session-${phase,,}.XXXXXX")"; then
  echo "$phase INCOMPLETE: cannot create a log directory; no samples ran."
  echo "$phase SUMMARY: requested=$runs attempted=0 passed=0 failed=0 incomplete=$runs"
  exit 2
fi
echo "$phase: filter=game_session expected_path=$expected_path expected_tests=$expected_tests logs=$log_dir"
echo "$phase LIMITS: workers=$workers per_process=${per_run_seconds}s batch=${batch_seconds}s kill_grace=${kill_grace_seconds}s"
deadline=$((SECONDS + batch_seconds))
attempted=0
passed=0
failed=0
incomplete=0
verified_pairs=0
declare -a active_timeouts=() codes=() statuses=() live_pids=() save_dirs=()
declare -a first_states=() last_states=() state_counts=() diagnostics_ok=()
declare -a selected_paths=() selection_counts=() test_totals=() test_passes=() test_failures=()

cleanup_children() {
  # Only timeout wrappers launched by this harness are signalled. Each wrapper
  # owns its Godot child and forwards termination; no name/global process kill.
  local child
  for child in "${active_timeouts[@]}"; do
    [[ -n "$child" ]] && kill -TERM "$child" 2>/dev/null
  done
  for child in "${active_timeouts[@]}"; do
    [[ -n "$child" ]] && wait "$child" 2>/dev/null
  done
}
trap cleanup_children EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

inspect_sample() {
  local index="$1" label log line selections=0 selected_path="" summaries=0
  local test_passed=0 test_failed=0 total states=0 pid="" directory="" first=0 last=0 valid=1
  local observed_pid observed_method observed_time observed_dir
  local -A methods=()
  printf -v label '%02d' "$index"
  log="$log_dir/run-$label.log"
  echo "$phase LOG BEGIN: sample=$label exit=${codes[$index]} file=$log"
  cat "$log"
  echo "$phase LOG END: sample=$label"

  while IFS= read -r line; do
    if [[ "$line" == 'TEST FILE: '* ]]; then
      selections=$((selections + 1))
      selected_path="${line#TEST FILE: }"
    elif [[ "$line" =~ ^TESTS:\ ([0-9]+)\ passed,\ ([0-9]+)\ failed$ ]]; then
      summaries=$((summaries + 1))
      test_passed="${BASH_REMATCH[1]}"
      test_failed="${BASH_REMATCH[2]}"
    elif [[ "$line" =~ ^TEST\ STATE:\ pid=([0-9]+)\ method=(test_[[:alnum:]_]+)\ unix_usec=([0-9]+)\ save_dir=(.+)$ ]]; then
      observed_pid="${BASH_REMATCH[1]}"
      observed_method="${BASH_REMATCH[2]}"
      observed_time="${BASH_REMATCH[3]}"
      observed_dir="${BASH_REMATCH[4]}"
      if ((states == 0)); then
        pid="$observed_pid"; directory="$observed_dir"; first="$observed_time"
      fi
      if [[ "$observed_pid" != "$pid" || "$observed_dir" != "$directory" \
          || -n "${methods[$observed_method]:-}" ]] || ((observed_time < last)); then
        valid=0
      fi
      methods[$observed_method]=1
      last="$observed_time"
      states=$((states + 1))
    fi
  done <"$log"
  total=$((test_passed + test_failed))
  if [[ "${codes[$index]}" == not-started || "${codes[$index]}" == 124 || "${codes[$index]}" == 137 ]] \
      || ((selections != 1 || summaries != 1 || total != expected_tests)) \
      || [[ "$selected_path" != "$expected_path" ]] \
      || { [[ "$phase" == OVERLAP ]] && ((states != expected_tests || valid != 1 || pid < 1)); }; then
    statuses[$index]=incomplete
  elif [[ "${codes[$index]}" != 0 ]] || ((test_failed > 0)) \
      || grep -Eq '^FAIL[[:space:]]|SCRIPT ERROR|Parse Error|^[[:space:]]*ERROR:' "$log"; then
    statuses[$index]=failed
  else
    statuses[$index]=passed
  fi
  live_pids[$index]="$pid"; save_dirs[$index]="$directory"
  first_states[$index]="$first"; last_states[$index]="$last"
  state_counts[$index]="$states"; diagnostics_ok[$index]="$valid"
  selected_paths[$index]="$selected_path"; selection_counts[$index]="$selections"
  test_totals[$index]="$total"; test_passes[$index]="$test_passed"; test_failures[$index]="$test_failed"
}

batches=$((runs / workers))
for ((batch=1; batch<=batches; batch++)); do
  remaining=$((deadline - SECONDS - kill_grace_seconds))
  duration=$per_run_seconds
  ((duration > remaining)) && duration=$remaining
  active_timeouts=()
  for ((worker=1; worker<=workers; worker++)); do
    index=$(((batch - 1) * workers + worker))
    printf -v label '%02d' "$index"
    log="$log_dir/run-$label.log"
    codes[$index]=not-started
    if ((duration > 0)); then
      timeout --kill-after="${kill_grace_seconds}s" "${duration}s" "$GODOT" \
        --headless --path . --script tools/run_tests.gd -- --filter=game_session >"$log" 2>&1 &
      active_timeouts[$worker]=$!
      attempted=$((attempted + 1))
      echo "$phase START: sample=$label batch=$batch worker=$worker timeout_pid=${active_timeouts[$worker]}"
    else
      printf 'INCOMPLETE: batch time budget exhausted before sample %s; no process started.\n' "$label" >"$log"
    fi
  done
  # Reap both owned children before another pair can start. No third Godot
  # process can overlap a pair, even when either member fails or times out.
  for ((worker=1; worker<=workers; worker++)); do
    index=$(((batch - 1) * workers + worker))
    if [[ -n "${active_timeouts[$worker]:-}" ]]; then
      wait "${active_timeouts[$worker]}"
      codes[$index]=$?
      active_timeouts[$worker]=""
    fi
    inspect_sample "$index"
  done
  active_timeouts=()
  if [[ "$phase" == OVERLAP ]]; then
    left=$((batch * 2 - 1)); right=$((batch * 2))
    if [[ -n "${live_pids[$left]}" && "${live_pids[$left]}" != "${live_pids[$right]}" \
        && "${save_dirs[$left]}" == "${save_dirs[$right]}" ]] \
        && ((state_counts[left] == expected_tests && state_counts[right] == expected_tests \
          && diagnostics_ok[left] == 1 && diagnostics_ok[right] == 1 \
          && first_states[left] < last_states[right] && first_states[right] < last_states[left])); then
      verified_pairs=$((verified_pairs + 1))
      echo "OVERLAP PAIR: pair=$batch verified=true pids=${live_pids[$left]},${live_pids[$right]} save_dir=${save_dirs[$left]} intervals=${first_states[$left]}..${last_states[$left]},${first_states[$right]}..${last_states[$right]}"
    else
      echo "OVERLAP PAIR: pair=$batch verified=false; distinct live PIDs, shared directory and overlapping test intervals were not all established."
      for index in "$left" "$right"; do
        [[ "${statuses[$index]}" != failed ]] && statuses[$index]=incomplete
      done
    fi
  fi
  for ((worker=1; worker<=workers; worker++)); do
    index=$(((batch - 1) * workers + worker))
    printf -v label '%02d' "$index"
    case "${statuses[$index]}" in
      passed) passed=$((passed + 1)) ;;
      failed) failed=$((failed + 1)) ;;
      incomplete) incomplete=$((incomplete + 1)) ;;
    esac
    echo "$phase RUN: sample=$label/$runs status=${statuses[$index]} exit=${codes[$index]} selected_files=${selection_counts[$index]} path=${selected_paths[$index]} tests=${test_totals[$index]} passed=${test_passes[$index]} failed=${test_failures[$index]}"
  done
done

echo "$phase SUMMARY: requested=$runs attempted=$attempted passed=$passed failed=$failed incomplete=$incomplete"
[[ "$phase" == OVERLAP ]] && echo "OVERLAP PAIRS: requested=$batches verified=$verified_pairs"
echo "$phase FAILURE LINES (complete logs are above):"
grep -H -E '^FAIL[[:space:]]|SCRIPT ERROR|Parse Error|^[[:space:]]*ERROR:|^INCOMPLETE:' "$log_dir"/run-*.log || true
if ((failed == 0 && incomplete == 0 && passed == runs)); then
  echo "$phase RESULT: not reproduced in $runs/$runs filtered runs; this does not establish a root cause."
  exit 0
fi
echo "$phase RESULT: $failed/$runs failed runs, $incomplete/$runs incomplete; no failed sample was retried."
exit 1
