#!/usr/bin/env bash
set -e

source dev-container-features-test-lib

check "rush is on PATH" rush --version
check "javac is JDK 17" bash -c "javac -version 2>&1 | grep -q 'javac 17'"
check "the App Inventor runtime is installed" bash -c 'ls "$RUSH_HOME"/ai2/*/'
check "an extension builds" bash -c 'cd "$(mktemp -d)" && rush --no-color create hello -p com.example -l java --ide intellij && cd hello && rush --no-color build && test -f out/com.example.hello.aix'

reportResults
