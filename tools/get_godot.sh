#!/usr/bin/env bash
# Downloads the standard official editor, which supports --headless.
# Only the final executable path goes to stdout, for GODOT="$(...)".
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION=4.7.2-stable
if [[ "$(uname -s)" != Linux ]]; then
    printf 'This downloader supports Linux only.\n' >&2
    exit 1
fi
case "$(uname -m)" in
    x86_64|amd64)
        arch=x86_64
        sha256=cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4
        ;;
    aarch64|arm64)
        arch=arm64
        sha256=5dd0d86405cf7e8adf79fb6377b38ba682a2846cb378ffe5364f38c01ad29b9d
        ;;
    *) printf 'Unsupported Linux architecture: %s\n' "$(uname -m)" >&2; exit 1 ;;
esac
for dependency in curl unzip sha256sum mktemp; do
    command -v "$dependency" >/dev/null 2>&1 || {
        printf 'Missing dependency: %s\n' "$dependency" >&2
        exit 1
    }
done

name="Godot_v${VERSION}_linux.${arch}"
mkdir -p "$ROOT/.tools"
download_dir="$(mktemp -d "$ROOT/.tools/download.XXXXXX")"
trap 'rm -rf -- "$download_dir"' EXIT
url="https://github.com/godotengine/godot-builds/releases/download/${VERSION}/${name}.zip"
printf 'Downloading official Godot %s (%s)...\n' "$VERSION" "$arch" >&2
curl --fail --location --retry 2 --connect-timeout 20 --max-time 300 "$url" -o "$download_dir/godot.zip" >&2
printf '%s  %s\n' "$sha256" "$download_dir/godot.zip" | sha256sum --check >&2
unzip -q "$download_dir/godot.zip" "$name" -d "$download_dir"
chmod +x "$download_dir/$name"
mv -f -- "$download_dir/$name" "$ROOT/.tools/$name"
printf '%s\n' "$ROOT/.tools/$name"
