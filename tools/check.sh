#!/usr/bin/env bash
# Serial, headless checks. GODOT is one executable path, not shell arguments.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT:-godot}"
EXPECTED_VERSION=4.7.2.stable
if ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
    printf 'Godot not found: %s. Set GODOT or run tools/get_godot.sh.\n' "$GODOT_BIN" >&2
    exit 1
fi
version="$("$GODOT_BIN" --version)"
if [[ "$version" != "$EXPECTED_VERSION" && "$version" != "$EXPECTED_VERSION".* ]]; then
    printf 'Expected Godot %s, got %s\n' "$EXPECTED_VERSION" "$version" >&2
    exit 1
fi

mkdir -p "$ROOT/.tools"
LOG_DIR="$(mktemp -d "$ROOT/.tools/check.XXXXXX")"
printf 'Check logs: %s\n' "$LOG_DIR"

run_checked() {
    local stage="$1"
    shift
    local status=0
    "$GODOT_BIN" --headless --path "$ROOT" "$@" >"$LOG_DIR/$stage.log" 2>&1 || status=$?
    cat "$LOG_DIR/$stage.log"
    if (( status != 0 )); then
        printf '%s failed (exit %s).\n' "$stage" "$status" >&2
        return "$status"
    fi
    # Godot can report parse/load errors while returning zero.
    if grep -Eiq '(^|[[:space:]])(SCRIPT ERROR:|ERROR:|Parse Error:|Compile Error:)' "$LOG_DIR/$stage.log"; then
        printf '%s reported engine/script errors.\n' "$stage" >&2
        return 1
    fi
}

run_checked import --editor --import
run_checked scripts --script res://tools/check_scripts.gd
run_checked gut --script res://addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit -gdisable_colors
printf 'All checks passed.\n'
