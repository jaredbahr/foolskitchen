#!/usr/bin/env bash
# Downloads the pinned Godot (tools/godot_version.txt) for Linux x86_64 into .tools/
# and prints the binary path. Safe to run repeatedly: it skips the download if present.
# Usage: bash tools/get_godot.sh        then: export GODOT="$(bash tools/get_godot.sh)"
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
ver="$(tr -d '[:space:]' < "$root/tools/godot_version.txt")"
dir="$root/.tools/godot-$ver"
bin="$dir/Godot_v${ver}-stable_linux.x86_64"
if [[ ! -x "$bin" ]]; then
  mkdir -p "$dir"
  url="https://downloads.godotengine.org/?version=${ver}&flavor=stable&slug=linux.x86_64.zip"
  echo "Downloading Godot $ver ..." >&2
  curl -fsSL --retry 3 -o "$dir/godot.zip" "$url"
  unzip -o -q "$dir/godot.zip" -d "$dir"
  rm -f "$dir/godot.zip"
  chmod +x "$bin"
fi
echo "$bin"
