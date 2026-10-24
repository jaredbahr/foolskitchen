#!/usr/bin/env bash
# Exports release builds into export/ and zips them for sharing.
# Usage: bash tools/export.sh [web|windows|all]   (default: all)
# Needs the pinned Godot (tools/get_godot.sh) and its export templates
# (tools/get_export_templates.sh).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
which="${1:-all}"
ver="$(tr -d '[:space:]' < tools/godot_version.txt)"
GODOT="${GODOT:-.tools/godot-$ver/Godot_v${ver}-stable_linux.x86_64}"
[[ -x "$GODOT" ]] || { echo "Godot not found. Run: bash tools/get_godot.sh"; exit 2; }
# Godot must never import or pack earlier builds.
mkdir -p export && touch export/.gdignore
timeout 300 "$GODOT" --headless --path . --import >/dev/null 2>&1 || true

export_one() { # preset, output file, zip name
  local preset="$1" out="$2" zipname="$3" log
  log="$(mktemp)"
  rm -rf "$(dirname "$out")" && mkdir -p "$(dirname "$out")"
  if ! timeout 600 "$GODOT" --headless --path . --export-release "$preset" "$out" >"$log" 2>&1 \
      || grep -qE "SCRIPT ERROR|Parse Error|^ERROR:" "$log" || [[ ! -s "$out" ]]; then
    cat "$log"
    echo "FAIL: export of '$preset' failed"
    exit 1
  fi
  (cd "$(dirname "$out")" && rm -f "../$zipname" && zip -q -r "../$zipname" .)
  echo "ok: export/$zipname ($(du -h "export/$zipname" | cut -f1))"
}

case "$which" in
  web) export_one "Web" export/web/index.html FoolsKitchen-web.zip ;;
  windows) export_one "Windows Desktop" export/windows/FoolsKitchen.exe FoolsKitchen-windows.zip ;;
  all)
    export_one "Web" export/web/index.html FoolsKitchen-web.zip
    export_one "Windows Desktop" export/windows/FoolsKitchen.exe FoolsKitchen-windows.zip
    ;;
  *) echo "usage: bash tools/export.sh [web|windows|all]"; exit 2 ;;
esac
