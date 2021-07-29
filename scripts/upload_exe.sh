#!/bin/bash

# NOTE: This script is only supposed to be run by Rush's CI (GH Actions)

set -e

pat="$1"

# @params:
#   $1 -> file path in GH repo relative to exe/
function fetch() {
  echo "$(curl -s -u shreyashsaitwal:$pat https://api.github.com/repos/shreyashsaitwal/pack/contents/exe/$1)"
}

# @params:
#   $1 -> file path in GH repo relative to exe/
#   $2 -> base64 encoded content of the file that is to be uploaded
#   $3 -> SHA of the file that is to be uploaded
function upload() {
  if  [ ! -d build ]; then
    mkdir build
  fi

  echo "Writing curl.args for $1..."
  cat > build/curl.args <<- EOF
{"message":"Update $1","content":"$2","sha":$3}
EOF

  echo "Uploading $1..."
  curl -X PUT -u shreyashsaitwal:"$pat" \
    -H "Accept: application/vnd.github.v3+json" \
    https://api.github.com/repos/shreyashsaitwal/pack/contents/exe/$1 \
    -d @build/curl.args
}

# @params
#   $1 -> is Linux or Windows?
#   $2 -> file to be encoded
function encode() {
  if (( "$1" )); then
    echo "$(base64 -w0 $2)"
  else
    echo "$(base64 -i $2)"
  fi
}

if [ "$OS" = "Windows_NT" ]; then
  res=$(fetch "win")
  exeSha=$(echo "$res" | jq '.[0].sha')
  swapSha=$(echo "$res" | jq '.[1].sha')

  upload "win/rush.exe" "$(encode true build/bin/rush.exe)" "$exeSha"
  upload "win/swap.exe" "$(encode true build/bin/swap.exe)" "$swapSha"
else
  case $(uname -sm) in
  "Darwin x86_64")
    res=$(fetch "mac")
    exeSha=$(echo "$res" | jq '.[0].sha')
    upload "mac/rush" "$(encode false build/bin/rush)" "$exeSha"
    ;;
  *)
    res=$(fetch "linux")
    exeSha=$(echo "$res" | jq '.[0].sha')
    upload "linux/rush" "$(encode true build/bin/rush)" "$exeSha"
    ;;
  esac
fi
