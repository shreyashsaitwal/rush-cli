#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
home="$root/build/test-home"

(cd "$root/processor" && ./gradlew -q build :processor:shadowJar :relocator:shadowJar)
mkdir -p "$home/libs" "$root/build"
cp "$root"/processor/processor/build/libs/processor-*[0-9].jar "$home/libs/processor.jar"
cp "$root"/processor/annotations/build/libs/annotations-*[0-9].jar "$home/libs/annotations.jar"
cp "$root"/processor/relocator/build/libs/relocator-*[0-9].jar "$home/libs/relocator.jar"

(cd "$root" && dart run build_runner build --delete-conflicting-outputs >/dev/null)
dart compile exe "$root/bin/rush.dart" -o "$root/build/rush" >/dev/null

RUSH_HOME=$home "$root/build/rush" deps sync --dev-deps >/dev/null

cd "$root"
RUSH_TEST_BIN="$root/build/rush" RUSH_HOME="$home" dart test --concurrency=1 "$@"
