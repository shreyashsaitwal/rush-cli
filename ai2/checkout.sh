#!/usr/bin/env bash
set -euo pipefail

tag=${1:?usage: checkout.sh <ai2-tag> <dir>}
src=${2:?usage: checkout.sh <ai2-tag> <dir>}

if [ ! -d "$src" ]; then
  git clone --depth 1 --branch "$tag" https://github.com/mit-cml/appinventor-sources "$src"
fi

make_git_describe_work_in_shallow_clone() {
  git -C "$src" -c user.name=rush -c user.email=rush@localhost \
    tag -f -a "$tag" -m "$tag" HEAD >/dev/null
}

make_git_describe_work_in_shallow_clone
