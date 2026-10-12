#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
home="$root/build/test-home"

build_tools() {
  (cd "$root/processor" && ./gradlew -q build :processor:shadowJar :relocator:shadowJar)
  mkdir -p "$home/libs" "$root/build"
  cp "$root"/processor/processor/build/libs/processor-*[0-9].jar "$home/libs/processor.jar"
  cp "$root"/processor/annotations/build/libs/annotations-*[0-9].jar "$home/libs/annotations.jar"
  cp "$root"/processor/relocator/build/libs/relocator-*[0-9].jar "$home/libs/relocator.jar"

  (cd "$root" && dart run build_runner build --delete-conflicting-outputs >/dev/null)
  dart compile exe "$root/bin/rush.dart" -o "$RUSH_TEST_BIN" >/dev/null
}

if [ -z "${RUSH_TEST_BIN:-}" ]; then
  RUSH_TEST_BIN="$root/build/rush"
  [ "${OS:-}" = Windows_NT ] && RUSH_TEST_BIN="$RUSH_TEST_BIN.exe"
  build_tools
fi

RUSH_HOME=$home "$RUSH_TEST_BIN" deps sync --dev-deps >/dev/null

cd "$root"
RUSH_TEST_BIN="$RUSH_TEST_BIN" RUSH_HOME="$home" dart test --concurrency=1 "$@"
