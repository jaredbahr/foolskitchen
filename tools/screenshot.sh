#!/usr/bin/env bash
# Renders the game (default: src/world/main.tscn) under a virtual display and
# saves PNGs to screens/ (git-ignored). Needs xvfb and Mesa (software OpenGL).
# Usage: bash tools/screenshot.sh [--out=dir] [--frames=120,400,900] [--speed=4] [--scene=res://...] [--quarter=0..3] [--open] [--fast=N] [--select=guest|owner] [--assign-owner=kitchen] [--f3] [--menu]
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
ver="$(tr -d '[:space:]' < tools/godot_version.txt)"
GODOT="${GODOT:-.tools/godot-$ver/Godot_v${ver}-stable_linux.x86_64}"
[[ -x "$GODOT" ]] || GODOT="$(bash tools/get_godot.sh)"
command -v xvfb-run >/dev/null || { echo "BLOCKED: xvfb-run is not preinstalled; a supported Xvfb/Mesa environment is required."; exit 2; }
out="screens"
for a in "$@"; do [[ "$a" == --out=* ]] && out="${a#--out=}"; done
mkdir -p "$out"
log="$out/capture.log"
set +e
timeout "${SCREENSHOT_TIMEOUT_SECONDS:-300}" xvfb-run -a -s "-screen 0 1600x900x24" "$GODOT" --path . --rendering-driver opengl3 \
  --resolution 1600x900 --audio-driver Dummy --script tools/screenshot.gd -- "--out=$out" "$@" 2>&1 \
  | tee "$log"
statuses=("${PIPESTATUS[@]}")
set -e
[[ "${statuses[0]}" -eq 0 ]] || { echo "FAIL: capture process exited ${statuses[0]}"; exit "${statuses[0]}"; }
[[ "${statuses[1]}" -eq 0 ]] || { echo "FAIL: capture log could not be written"; exit "${statuses[1]}"; }
if grep -E "SCRIPT ERROR|Parse Error|^[[:space:]]*ERROR:" "$log" >/dev/null; then
  echo "FAIL: engine/script errors in capture log"
  exit 1
fi
ls "$out"/*.png 2>/dev/null
