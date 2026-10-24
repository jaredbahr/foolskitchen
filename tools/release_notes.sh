#!/usr/bin/env bash
# Prints the whole CHANGELOG section for one version (the release's
# "What's new"), word for word. Fails if the section is missing or empty, so a
# release can never ship with partial or missing notes.
# Usage: bash tools/release_notes.sh v0.1.0 [CHANGELOG.md]
set -euo pipefail
version="${1:?version, for example v0.1.0}"
file="${2:-CHANGELOG.md}"
notes="$(awk -v v="$version" '
  /^## / { if (found) exit; split($0, w, " "); if (w[2] == v) { found = 1; next } }
  found { print }
  END { if (!found) exit 3 }
' "$file")" || { echo "No '## $version' section in $file. Rename '## Unreleased' to '## $version' first." >&2; exit 1; }
if ! grep -qE '^- ' <<<"$notes"; then
  echo "The '## $version' section in $file has no entries." >&2
  exit 1
fi
# Trim leading and trailing blank lines.
printf '%s\n' "$notes" | awk 'NF { started = 1 } started { lines[++n] = $0 } END { while (n > 0 && lines[n] ~ /^[[:space:]]*$/) n--; for (i = 1; i <= n; i++) print lines[i] }'
