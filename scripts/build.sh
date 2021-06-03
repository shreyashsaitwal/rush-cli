#!/bin/bash

set -eu

# This is the version name of this version of Rush
version=$1

# This is the GitHub Personal Access token
token=$2

# Write version.dart file
function writeVersionDart() {
  file='./lib/version.dart'

  printf "// Auto-generated; DO NOT modify\n" > $file
  printf "const rushVersion = '$version';\n" >> $file
  printf "const rushBuiltOn = '$(date '+%Y-%m-%d %H:%M:%S')';\n" >> $file

  echo 'Generated lib/version.dart'
}
writeVersionDart

# Write env.dart
function writeEnvDart() {
  file='./lib/env.dart'

  printf "// Auto-generated; DO NOT modify\n" > $file
  printf "const GH_PAT = '$token';\n" >> $file

  echo 'Generated lib/env.dart'
}
writeEnvDart

function compileExes() {
  if [ "$OS" = "Windows_NT" ]; then
    # Compile swap.exe
    dart compile exe -o build/bin/swap.exe bin/swap.dart
    ext=".exe"
  else
    ext=""
  fi

  # Compile Rush executable
  dart compile exe -o build/bin/rush$ext bin/rush.dart
}
compileExes
