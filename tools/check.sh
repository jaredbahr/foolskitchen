#!/usr/bin/env bash
# Project checks. Must pass before every push and in CI.
#   1. headless import (builds the .godot cache, catches broken resources)
#   2. compile check of every .gd script, with autoloads loaded (tools/parse_all.gd)
#   3. unit tests (tools/run_tests.gd)
# Any "SCRIPT ERROR", "Parse Error" or "ERROR:" line in the output fails the check, so code
# paths exercised by tests must not push_error() on purpose (test the return value instead).
# Each step has a 5-minute timeout so a hung script fails instead of blocking CI.
# Godot binary: $GODOT, else .tools/ (from tools/get_godot.sh), else `godot` on PATH.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
ver="$(tr -d '[:space:]' < tools/godot_version.txt)"
GODOT="${GODOT:-}"
if [[ -z "$GODOT" ]]; then
  local_bin=".tools/godot-$ver/Godot_v${ver}-stable_linux.x86_64"
  if [[ -x "$local_bin" ]]; then GODOT="$local_bin"; else GODOT="godot"; fi
fi
command -v "$GODOT" >/dev/null 2>&1 || [[ -x "$GODOT" ]] || { echo "Godot not found. Run: bash tools/get_godot.sh"; exit 2; }

fail=0
log="$(mktemp)"
trap 'rm -f "$log"' EXIT

has_errors() { grep -E "SCRIPT ERROR|Parse Error|^ERROR:|^\s*ERROR:" "$1" >/dev/null; }

echo "== import"
timeout 300 "$GODOT" --headless --path . --import >"$log" 2>&1
code=$?
if [[ $code -ne 0 ]] || has_errors "$log"; then cat "$log"; echo "FAIL: import"; fail=1; else echo "ok"; fi

echo "== parse"
timeout 300 "$GODOT" --headless --path . --script tools/parse_all.gd >"$log" 2>&1
code=$?
if [[ $code -ne 0 ]] || has_errors "$log"; then cat "$log"; echo "FAIL: parse"; fail=1; else tail -1 "$log"; fi

echo "== tests"
timeout 300 "$GODOT" --headless --path . --script tools/run_tests.gd >"$log" 2>&1
code=$?
cat "$log"
if [[ $code -ne 0 ]] || has_errors "$log"; then echo "FAIL: tests"; fail=1; fi

echo "== release notes"
if ! bash tools/test_release_notes.sh; then fail=1; fi

if [[ $fail -eq 0 ]]; then echo "ALL CHECKS PASSED"; else echo "CHECKS FAILED"; fi
exit $fail
