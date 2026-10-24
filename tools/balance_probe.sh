#!/usr/bin/env bash
# Manual balance comparison. Keep probe state out of the player's user://.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
ver="$(tr -d '[:space:]' < tools/godot_version.txt)"
GODOT="${GODOT:-}"
if [[ -z "$GODOT" ]]; then
  local_bin=".tools/godot-$ver/Godot_v${ver}-stable_linux.x86_64"
  if [[ -x "$local_bin" ]]; then GODOT="$local_bin"; else GODOT="godot"; fi
fi
command -v "$GODOT" >/dev/null 2>&1 || [[ -x "$GODOT" ]] || { echo "Godot not found. Run: bash tools/get_godot.sh" >&2; exit 2; }

probe_tmp_base="${TMPDIR:-/tmp}"
probe_data_home="$(mktemp -d "$probe_tmp_base/fk-balance-XXXXXXXX")"
case "$probe_data_home" in
  "$probe_tmp_base"/fk-balance-*) ;;
  *) echo "Unsafe probe data path" >&2; exit 2 ;;
esac
trap 'rm -rf -- "$probe_data_home"' EXIT
export XDG_DATA_HOME="$probe_data_home"
export FK_PROBE_SHA="$(git rev-parse HEAD)"
"$GODOT" --headless --path . --script tools/balance_probe.gd -- "$@"
