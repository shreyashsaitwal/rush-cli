#!/bin/bash

# NOTE: This script is only supposed to be run by Rush's CI (GH Actions)

set -e

pat=$1

function fetch() {
  echo $(curl -s \
      -u "shreyashsaitwal:$pat" \
      -H "Accept: application/vnd.github.v3+json" \
      https://api.github.com/repos/shreyashsaitwal/rush-pack/contents/exe/$1)
}

function upload() {
  curl -X PUT \
    -u "shreyashsaitwal:$pat" \
    -H "Accept: application/vnd.github.v3+json" \
    https://api.github.com/repos/shreyashsaitwal/rush-pack/contents/$1 \
    -d "{\"message\":\"Update $1\",\"content\":\"$2\",\"sha\":"$3"}"
}

function encode() {
  echo $(base64 -w0 $1)
}

if [ "$OS" = "Windows_NT" ]; then
  res=$(fetch "win")
  exeSha=$(echo $res | jq '.[0].sha')
  swapSha=$(echo $res | jq '.[1].sha')

  upload "win/rush.exe" $(encode build/bin/rush.exe) $exeSha
  upload "win/swap.exe" $(encode build/bin/swap.exe) $swapSha
else
  case $(uname -sm) in
    "Darwin x86_64" | "Darwin arm64")
      target="mac" ;;
    *)
      target="linux" ;;
  esac

  res=$(fetch "$target")
  exeSha=$(echo $res | jq '.[0].sha')
  upload "mac/rush" $(encode build/bin/rush) $exeSha
fi
