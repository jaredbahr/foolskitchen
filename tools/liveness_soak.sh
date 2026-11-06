#!/usr/bin/env bash
# Manual movement liveness soak (#306): real production days, every service
# tick checked for anyone who wants to move but makes no physical progress.
#   bash tools/liveness_soak.sh [--jobs N] [--seeds 1-40] [--setups a,b] [--days 14] [--edits both|true|false] [--limit 600]
#     [--inspector true]   (a health inspector visit on every open day)
# Splits seeds across N parallel Godot processes (default 3), each with its own
# user:// directory, and prints SOAK_CASE rows, STUCK_DUMP blocks and a summary.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
ver="$(tr -d '[:space:]' < tools/godot_version.txt)"
GODOT="${GODOT:-}"
if [[ -z "$GODOT" ]]; then
  local_bin=".tools/godot-$ver/Godot_v${ver}-stable_linux.x86_64"
  if [[ -x "$local_bin" ]]; then GODOT="$local_bin"; else GODOT="godot"; fi
fi
jobs=3; seeds="1-40"; setups="default,coffee_shop,bar,fryer_coffee,expanded_tables,expanded_staffed"
days=14; edits="both"; limit=600; out=""; inspector="false"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --jobs) jobs="$2";; --seeds) seeds="$2";; --setups) setups="$2";; --days) days="$2";;
    --edits) edits="$2";; --limit) limit="$2";; --out) out="$2";; --inspector) inspector="$2";;
    *) echo "unknown option $1" >&2; exit 2;;
  esac
  shift 2
done
# Expand the seed list, then deal seeds round-robin to the jobs.
all=()
IFS=',' read -ra parts <<< "$seeds"
for p in "${parts[@]}"; do
  if [[ "$p" == *-* ]]; then for ((s=${p%-*}; s<=${p#*-}; s++)); do all+=("$s"); done; else all+=("$p"); fi
done
variants=()
case "$edits" in both) variants=(false true);; *) variants=("$edits");; esac
work="$(mktemp -d "${TMPDIR:-/tmp}/fk-liveness-XXXXXXXX")"
trap 'rm -rf -- "$work"' EXIT
pids=()
for ((j = 0; j < jobs; j++)); do
  mine=""
  for ((k = j; k < ${#all[@]}; k += jobs)); do mine+="${all[$k]},"; done
  [[ -z "$mine" ]] && continue
  mkdir -p "$work/home$j"
  (
    for v in "${variants[@]}"; do
      XDG_DATA_HOME="$work/home$j" "$GODOT" --headless --path . --script tools/liveness_soak.gd -- \
        --seeds "${mine%,}" --setups "$setups" --days "$days" --edits "$v" --limit "$limit" --inspector "$inspector"
    done
  ) >"$work/job$j.log" 2>&1 &
  pids+=($!)
done
for pid in "${pids[@]}"; do wait "$pid"; done
cat "$work"/job*.log > "$work/all.log"
[[ -n "$out" ]] && cp "$work/all.log" "$out"
grep -E "^(STUCK_DUMP|  |END_DUMP)" "$work/all.log" | head -400
python3 - "$work/all.log" <<'PY'
import json, sys
rows = [json.loads(l.split(" ", 1)[1]) for l in open(sys.argv[1]) if l.startswith("SOAK_CASE ")]
errors = [r for r in rows if "error" in r]
stuck = [r for r in rows if r.get("stuck_episodes", 0) > 0]
print("runs=%d agent_days=%d stuck_runs=%d stuck_episodes=%d max_no_progress=%d max_goal_wait=%d errors=%d served=%d lost=%d gave_up=%d squeezes=%d" % (
    len(rows), sum(r["agent_days"] for r in rows), len(stuck), sum(r["stuck_episodes"] for r in rows),
    max([r["max_no_progress"] for r in rows] or [0]), max([r["max_goal_wait"] for r in rows] or [0]),
    len(errors), sum(r["served"] for r in rows), sum(r["lost"] for r in rows),
    sum(r["reasons"].get("no_way_through", 0) for r in rows),
    sum(r.get("escapes", {}).get("squeeze", 0) for r in rows)))
if any("inspector_visits" in r for r in rows):
    print("inspector visits=%d removed=%d max_stall=%d" % (sum(r.get("inspector_visits", 0) for r in rows),
        sum(r.get("inspector_removed", 0) for r in rows), max(r.get("inspector_max_stall", 0) for r in rows)))
for r in stuck + errors:
    print("  %s seed=%d edits=%s episodes=%d max=%d %s" % (r["setup"], r["seed"], r["edits"], r["stuck_episodes"], r["max_no_progress"], r.get("error", "")))
PY
