#!/usr/bin/env bash
set -euo pipefail

work=$(realpath -m "${1:?usage: fonts.sh <work-dir>}")
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
rush=${RUSH_BIN:-$root/build/rush}
fixture=$here/fixtures/fonts
export RUSH_HOME=${RUSH_HOME:-$root/build/test-home}

rm -rf "$work" && mkdir -p "$work"
(cd "$work" && "$rush" --no-color create fonts -p com.example -l java --ide intellij >/dev/null)
project=$work/fonts
cp "$fixture/rush.yml" "$project/rush.yml"
cp -r "$fixture/res" "$project/res"
cp "$fixture/Fonts.java" "$project/src/com/example/fonts/Fonts.java"
(cd "$project" && "$rush" --no-color build > "$work/build.log" 2>&1) ||
  { echo "Rush build failed, see $work/build.log" >&2; exit 1; }
aix=$project/out/com.example.fonts.aix

"$here/merge-check.sh" "$work/merge" "$aix"
"$here/build-apk.sh" "$work/app" "$aix"
"$here/run-apk.sh" "$work/app/out/Smoke.apk" 8 "Fonts ready: numbers=true family=true style=true"
