#!/usr/bin/env bash
# Renders the game (default: src/world/main.tscn) under a virtual display and
# saves PNGs to screens/ (git-ignored). Needs xvfb and Mesa (software OpenGL).
# Usage: bash tools/screenshot.sh [--out=dir] [--frames=120,400,900] [--speed=4] [--scene=res://...] [--quarter=0..3] [--open] [--fast=N] [--select=guest|owner] [--assign-owner=kitchen] [--f3] [--menu] [--settings] [--report] [--build=green|red] [--paint]
# --staff --speed=0 shows the production Staff panel without changing its roster.
# --stock --speed=0 --frames=12 shows the morning Stock panel; --stock --open --fast=2 --speed=0 --frames=30 shows the Sold out tag; add --report (--fast=100 --frames=60) for the report's Low stock section.
# --settings --speed=0 --frames=12 shows Settings at the usual 1600x900 / 100%.
# --settings-world --speed=0 --frames=90 selects 150%, uses keyboard Close and shows the world.
# --hud-layout --window-size=1280x720|1600x900 --speed=0 --frames=12,90 captures 125%, then 150%.
# --report --open --fast=100 --speed=0 --frames=60 captures a real closed-day report.
# --door-queue --open --fast=8 --speed=1 --frames=240 zooms a real queue, or records its absence at the entry.
# --loan-review --speed=0 --frames=12,90 captures an explicit loss fixture's bank report, then next-morning Loan HUD.
# --milestone-review --speed=0 --frames=12,90 captures Goals, then an explicit close-data reward fixture.
# --catalogue-review=rustic|modern --speed=0 --frames=90,120 captures real previews, then the furnishing fixture.
# --diner-review --speed=0 --frames=12,90 captures six native comparisons, then real seated diner guests.
# --walls=place --speed=0 --frames=12 holds a dragged wall run (ghost + cost); --walls=room --open --fast=10 --speed=1 --frames=150 [--quarter=0] shows a built room, Walls Up or Cutaway.
# --expand=drag --speed=0 --frames=12 holds a dragged floor rectangle on the lot (ghost + cost + lot outline); --expand=shop --open --fast=10 --speed=1 --frames=150 [--quarter=0] shows the finished L-shaped shop.
# --rooms=tool|refused --speed=0 --frames=30 shows the Rooms tool tints or a refused kitchen seat; --rooms=restroom --open --fast=10 --speed=1 --frames=200 pauses on a guest walking round the kitchen to the restroom.
# Build previews use the production morning input API without buying or saving.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
ver="$(tr -d '[:space:]' < tools/godot_version.txt)"
GODOT="${GODOT:-.tools/godot-$ver/Godot_v${ver}-stable_linux.x86_64}"
[[ -x "$GODOT" ]] || GODOT="$(bash tools/get_godot.sh)"
command -v xvfb-run >/dev/null || { echo "BLOCKED: xvfb-run is not preinstalled; a supported Xvfb/Mesa environment is required."; exit 2; }
out="screens"
settings_capture=false
hud_layout=false
window_size="1600x900"
window_size_requested=false
for a in "$@"; do
  [[ "$a" == --out=* ]] && out="${a#--out=}"
  [[ "$a" == --settings || "$a" == --settings-world || "$a" == --loan-review || "$a" == --milestone-review || "$a" == --diner-review ]] && settings_capture=true
  [[ "$a" == --catalogue-review=* ]] && settings_capture=true
  if [[ "$a" == --hud-layout ]]; then
    hud_layout=true
    settings_capture=true
  fi
  if [[ "$a" == --window-size* ]]; then
    if "$window_size_requested" || [[ "$a" != --window-size=1280x720 && "$a" != --window-size=1600x900 ]]; then
      echo "FAIL: --window-size supports one 1280x720 or 1600x900 value"
      exit 1
    fi
    window_size="${a#--window-size=}"
    window_size_requested=true
  fi
done
if "$window_size_requested" && ! "$hud_layout"; then
  echo "FAIL: --window-size requires --hud-layout"
  exit 1
fi
# Keep explicit UI/window captures and preference changes isolated from other runs.
if "$settings_capture"; then
  settings_data="$(mktemp -d)"
  export XDG_DATA_HOME="$settings_data"
  trap 'rm -rf -- "$settings_data"' EXIT
fi
mkdir -p "$out"
log="$out/capture.log"
set +e
timeout "${SCREENSHOT_TIMEOUT_SECONDS:-300}" xvfb-run -a -s "-screen 0 ${window_size}x24" "$GODOT" --path . --rendering-driver opengl3 \
  --resolution "$window_size" --audio-driver Dummy --script tools/screenshot.gd -- "--out=$out" "$@" 2>&1 \
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
