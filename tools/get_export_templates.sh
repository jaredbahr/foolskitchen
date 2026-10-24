#!/usr/bin/env bash
# Installs the export templates for the pinned Godot version (Web and Windows
# only, to keep the cache small) and prints the install directory.
# Safe to run repeatedly: it skips the download when the templates are present.
# Usage: bash tools/get_export_templates.sh
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
ver="$(tr -d '[:space:]' < "$root/tools/godot_version.txt")"
dest="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/${ver}.stable"
needed=(web_nothreads_release.zip windows_release_x86_64.exe version.txt)
missing=0
for f in "${needed[@]}"; do [[ -f "$dest/$f" ]] || missing=1; done
if [[ "$missing" == 1 ]]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  url="https://github.com/godotengine/godot/releases/download/${ver}-stable/Godot_v${ver}-stable_export_templates.tpz"
  echo "Downloading export templates $ver (about 1.3 GB) ..." >&2
  curl -fsSL --retry 3 -o "$tmp/templates.tpz" "$url"
  mkdir -p "$dest"
  for f in "${needed[@]}" web_nothreads_debug.zip windows_debug_x86_64.exe; do
    unzip -o -q -j "$tmp/templates.tpz" "templates/$f" -d "$dest"
  done
fi
echo "$dest"
