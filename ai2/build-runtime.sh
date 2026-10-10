#!/usr/bin/env bash
set -euo pipefail

tag=${1:?usage: build-runtime.sh <ai2-tag> [work-dir]}
work=$(realpath -m "${2:-build/ai2-$tag}")
here=$(cd "$(dirname "$0")" && pwd)
src="$work/appinventor-sources"

mkdir -p "$work"
if [ ! -d "$src" ]; then
  git clone --depth 1 --branch "$tag" https://github.com/mit-cml/appinventor-sources "$src"
fi

make_git_describe_work_in_shallow_clone() {
  git -C "$src" -c user.name=rush -c user.email=rush@localhost \
    tag -f -a "$tag" -m "$tag" HEAD >/dev/null
}

make_git_describe_work_in_shallow_clone

(cd "$src/appinventor/components" && ant AndroidRuntime)

python3 -I "$here/mkruntime.py" "$src/appinventor" "$tag" "$work/ai2-runtime-$tag.zip"
sha256sum "$work/ai2-runtime-$tag.zip"
