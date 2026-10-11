#!/usr/bin/env bash
set -euo pipefail

work=$(realpath -m "${1:?usage: coexist.sh <work-dir>}")
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
rush=${RUSH_BIN:-$root/build/rush}
adb=${ADB:-$HOME/Android/sdk/platform-tools/adb}
export RUSH_HOME=${RUSH_HOME:-$root/build/test-home}

rm -rf "$work" && mkdir -p "$work/projects" "$work/aix" "$work/apps"
failures=0

build_extension() {
  local name=$1 class=${1^}
  local project=$work/projects/$name fixture=$here/fixtures/$name
  (cd "$work/projects" && "$rush" --no-color create "$name" -p com.example -l kotlin --ide intellij >/dev/null)
  [ -f "$fixture/rush.yml" ] && cp "$fixture/rush.yml" "$project/rush.yml"
  [ -f "$fixture/$class.kt" ] && cp "$fixture/$class.kt" "$project/src/com/example/$name/$class.kt"
  for mode in plain optimized; do
    local flags=()
    [ $mode = optimized ] && flags=(--optimize)
    if (cd "$project" && "$rush" --no-color build "${flags[@]}" > "$work/aix/$name-$mode.log" 2>&1); then
      cp "$project/out/com.example.$name.aix" "$work/aix/$name-$mode.aix"
    else
      echo "FAIL build $name ($mode), see $work/aix/$name-$mode.log"
      failures=$((failures + 1))
    fi
  done
}

check() {
  local app=$1; shift
  local aixes=() expected=()
  for extension in "$@"; do
    aixes+=("$work/aix/$extension.aix")
    local name=${extension%-*}
    [ -f "$here/fixtures/$name/${name^}.kt" ] && expected+=("${name^} ready")
  done
  if ! "$here/build-apk.sh" "$work/apps/$app" "${aixes[@]}" > "$work/apps/$app.log" 2>&1; then
    echo "FAIL $app: $(grep -m1 -oE 'Type [^ ]+ is defined multiple times|ERROR.*' "$work/apps/$app.log")"
    failures=$((failures + 1))
    return
  fi
  if ! "$here/run-apk.sh" "$work/apps/$app/out/Smoke.apk" > "$work/apps/$app.run.log" 2>&1; then
    echo "FAIL $app: $(grep -m1 -oE '[A-Za-z.]+(Error|Exception): .{0,120}' "$work/apps/$app.run.log")"
    failures=$((failures + 1))
    return
  fi
  local logs
  logs=$("$adb" logcat -d -s RushE2E:I)
  for line in "${expected[@]}"; do
    if ! grep -q "$line" <<< "$logs"; then
      echo "FAIL $app: no \"$line\" in logcat"
      failures=$((failures + 1))
      return
    fi
  done
  echo "ok   $app"
}

for name in alpha beta delta epsilon gamma theta; do build_extension "$name"; done

check kotlin alpha-plain beta-plain
check kotlin-optimized alpha-optimized beta-optimized
check kotlin-versions delta-plain epsilon-plain
check kotlin-versions-optimized delta-optimized epsilon-optimized
check media3 gamma-plain theta-plain
check media3-reversed theta-plain gamma-plain
check media3-optimized gamma-optimized theta-optimized
check mixed alpha-optimized delta-plain epsilon-optimized gamma-plain theta-optimized

[ "$failures" -eq 0 ] || { echo "$failures failure(s)"; exit 1; }
