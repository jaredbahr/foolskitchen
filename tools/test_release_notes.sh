#!/usr/bin/env bash
# Tests tools/release_notes.sh against tests/fixtures/changelog_release.md.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
fx="$root/tests/fixtures/changelog_release.md"
notes="$root/tools/release_notes.sh"
fail() { echo "FAIL release notes: $1"; exit 1; }
out="$(bash "$notes" v0.2.0 "$fx")" || fail "v0.2.0 should succeed"
[[ "$out" == $'### Players\n- A newer change. (#5)\n\n### Under the hood\n- Tooling. (#6)' ]] || fail "v0.2.0 section wrong: $out"
out="$(bash "$notes" v0.1.0 "$fx")" || fail "v0.1.0 (a middle section) should succeed"
[[ "$out" == $'### Players\n- The first playable day. (#1)' ]] || fail "v0.1.0 section wrong: $out"
bash "$notes" v9.9.9 "$fx" >/dev/null 2>&1 && fail "a missing version must fail"
bash "$notes" v0.0.1 "$fx" >/dev/null 2>&1 && fail "an empty last section must fail"
bash "$notes" v0.2 "$fx" >/dev/null 2>&1 && fail "a version prefix must not match"
echo "release notes ok"
