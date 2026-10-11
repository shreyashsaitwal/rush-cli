#!/usr/bin/env bash
set -euo pipefail

tag=${AI2_TAG:-v206}
cache=${RUSH_E2E_CACHE:-$HOME/.cache/rush-e2e}
here=$(cd "$(dirname "$0")" && pwd)
src="$cache/appinventor-$tag"
libs="$src/appinventor/buildserver/build/run/lib"

if [ ! -f "$libs/BuildServer.jar" ]; then
  java11=${JAVA11_HOME:-$(ls -d "$HOME"/.sdkman/candidates/java/11* 2>/dev/null | head -1)}
  [ -d "$java11" ] || { echo "JDK 11 is required: set JAVA11_HOME" >&2; exit 1; }
  mkdir -p "$cache"
  "$here/../../ai2/checkout.sh" "$tag" "$src" >&2
  (
    export JAVA_HOME=$java11 PATH=$java11/bin:$PATH
    cd "$src/appinventor/components" && ant AndroidRuntime >&2
    cd "$src/appinventor/buildserver" && ant BuildServer >&2
  )
fi

echo "$src/appinventor"
