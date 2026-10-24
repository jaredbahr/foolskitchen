#!/usr/bin/env bash
# Renders the game (default: src/world/main.tscn) under a virtual display and
# saves PNGs to screens/ (git-ignored). Needs xvfb and Mesa (software OpenGL).
# Usage: bash tools/screenshot.sh [--out=dir] [--frames=120,400,900] [--speed=4] [--scene=res://...]
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
ver="$(tr -d '[:space:]' < tools/godot_version.txt)"
GODOT="${GODOT:-.tools/godot-$ver/Godot_v${ver}-stable_linux.x86_64}"
[[ -x "$GODOT" ]] || GODOT="$(bash tools/get_godot.sh)"
command -v xvfb-run >/dev/null || { echo "xvfb-run not found (apt-get install xvfb libgl1-mesa-dri)"; exit 2; }
out="screens"
for a in "$@"; do [[ "$a" == --out=* ]] && out="${a#--out=}"; done
timeout 300 xvfb-run -a -s "-screen 0 1600x900x24" "$GODOT" --path . --rendering-driver opengl3 \
  --resolution 1600x900 --audio-driver Dummy --script tools/screenshot.gd -- "--out=$out" "$@" 2>&1 \
  | grep -E "^saved|ERROR|SCRIPT ERROR" || true
ls "$out"/*.png 2>/dev/null
