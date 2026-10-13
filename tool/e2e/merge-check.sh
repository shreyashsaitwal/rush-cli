#!/usr/bin/env bash
set -euo pipefail

work=$(realpath -m "${1:?usage: merge-check.sh <work-dir> <aix>...}")
shift
[ $# -gt 0 ] || { echo "usage: merge-check.sh <work-dir> <aix>..." >&2; exit 2; }
here=$(cd "$(dirname "$0")" && pwd)
appinventor=$("$here/buildserver.sh")
classpath="$appinventor/buildserver/build/run/lib/*"

rm -rf "$work" && mkdir -p "$work/aars" "$work/classes" "$work/merged"
for aix in "$@"; do
  unzip -q -o "$aix" '*/aars/*.aar' -d "$work/aix"
done
resDirs=()
for aar in "$work"/aix/*/aars/*.aar; do
  dir="$work/aars/$(basename "$aar" .aar)"
  unzip -q -o "$aar" 'res/*' -d "$dir" 2>/dev/null || continue
  resDirs+=("$dir/res")
done

javac -d "$work/classes" -cp "$classpath" "$here/MergeCheck.java"
java -cp "$work/classes:$classpath" MergeCheck "$work/merged" "${resDirs[@]}"
