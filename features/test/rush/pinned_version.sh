#!/usr/bin/env bash
set -e

source dev-container-features-test-lib

check "rush is the pinned version" bash -c "rush --version | grep -q 2.0.0"

reportResults
