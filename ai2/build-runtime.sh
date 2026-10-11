#!/usr/bin/env bash
set -euo pipefail

tag=${1:?usage: build-runtime.sh <ai2-tag> [work-dir]}
work=$(realpath -m "${2:-build/ai2-$tag}")
here=$(cd "$(dirname "$0")" && pwd)
src="$work/appinventor-sources"

mkdir -p "$work"
"$here/checkout.sh" "$tag" "$src"
(cd "$src/appinventor/components" && ant AndroidRuntime)

python3 -I "$here/mkruntime.py" "$src/appinventor" "$tag" "$work/ai2-runtime-$tag.zip"
sha256sum "$work/ai2-runtime-$tag.zip"
