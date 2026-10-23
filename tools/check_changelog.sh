#!/usr/bin/env bash
# Fails unless the changes between BASE and HEAD add at least one "- " entry to
# CHANGELOG.md, so every merged change reaches the release notes ("What's new").
# Usage: bash tools/check_changelog.sh <base-sha> <head-sha>
# CI skips this when the PR has the "no-changelog" label (for example a pure
# changelog fix or a revert).
set -euo pipefail
base="${1:?base sha}"
head="${2:?head sha}"
if ! git diff --name-only "$base" "$head" | grep -qx "CHANGELOG.md"; then
  echo "CHANGELOG.md was not changed. Add a line under '## Unreleased' describing this PR (see the top of CHANGELOG.md)."
  exit 1
fi
if ! git diff -U0 "$base" "$head" -- CHANGELOG.md | grep -qE '^\+- '; then
  echo "CHANGELOG.md changed, but no new '- ' entry was added under '## Unreleased'."
  exit 1
fi
echo "changelog ok"
