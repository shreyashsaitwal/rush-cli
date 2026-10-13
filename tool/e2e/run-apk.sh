#!/usr/bin/env bash
set -euo pipefail

apk=${1:?usage: run-apk.sh <apk> [seconds] [expected log line]}
seconds=${2:-8}
expected=${3:-}
package=dev.rush.e2e.Smoke
adb=${ADB:-$HOME/Android/sdk/platform-tools/adb}

"$adb" get-state >/dev/null
"$adb" uninstall "$package" >/dev/null 2>&1 || true
"$adb" install "$apk" >/dev/null
"$adb" logcat -c
"$adb" shell monkey -p "$package" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep "$seconds"

if "$adb" logcat -d | grep -A15 "FATAL EXCEPTION" | grep -q "Process: $package"; then
  "$adb" logcat -d | grep -A30 "FATAL EXCEPTION" >&2
  echo "App crashed" >&2
  exit 1
fi
if [ -n "$expected" ] && ! "$adb" logcat -d -s RushE2E:I | grep -qF "$expected"; then
  "$adb" logcat -d -s RushE2E:I >&2
  echo "No \"$expected\" in the log" >&2
  exit 1
fi
echo "App ran for ${seconds}s without crashing"
