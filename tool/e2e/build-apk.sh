#!/usr/bin/env bash
set -euo pipefail

work=$(realpath -m "${1:?usage: build-apk.sh <work-dir> <aix>...}")
shift
[ $# -gt 0 ] || { echo "usage: build-apk.sh <work-dir> <aix>..." >&2; exit 2; }
here=$(cd "$(dirname "$0")" && pwd)
appinventor=$("$here/buildserver.sh")
java11=${JAVA11_HOME:-$(ls -d "$HOME"/.sdkman/candidates/java/11* | head -1)}

rm -rf "$work" && mkdir -p "$work/project" "$work/out" "$work/tmp/lib64" "$work/dex"
aixes=()
for aix in "$@"; do aixes+=("$(realpath "$aix")"); done
echo "Components: $(python3 -I "$here/mkproject.py" "$work/project" "${aixes[@]}")"
(cd "$work/project" && zip -q -r -D "$work/project.aia" .)
cp "$appinventor/lib/android/tools/linux/lib64/libc++.so" "$work/tmp/lib64/"

if ! "$java11/bin/java" -Djava.io.tmpdir="$work/tmp" -Dfile.encoding=UTF-8 -Djava.awt.headless=true \
  -cp "$appinventor/buildserver/build/run/lib/*" com.google.appinventor.buildserver.Main \
  --inputZipFile "$work/project.aia" --userName e2e --outputDir "$work/out" --dexCacheDir "$work/dex" \
  > "$work/build.log" 2>&1; then
  grep -E '^Type .* defined multiple times|ERROR' "$work/build.log" | head -5 >&2
  echo "APK build failed, see $work/build.log" >&2
  exit 1
fi

ls "$work"/out/*.apk
