#!/usr/bin/env bash
set -euo pipefail

rush_home=/usr/local/rush
user="${_REMOTE_USER:-root}"

if [ "$(uname -m)" != x86_64 ]; then
  echo "Rush runs on x86_64 Linux, not $(uname -m)." >&2
  exit 1
fi

missing=()
command -v curl >/dev/null || missing+=(curl ca-certificates)
command -v unzip >/dev/null || missing+=(unzip)
if [ ${#missing[@]} -gt 0 ]; then
  apt-get update -y
  apt-get install -y --no-install-recommends "${missing[@]}"
  rm -rf /var/lib/apt/lists/*
fi

if [ "$VERSION" = latest ]; then
  url="https://github.com/shreyashsaitwal/rush-cli/releases/latest/download/rush-x86_64-linux.zip"
else
  url="https://github.com/shreyashsaitwal/rush-cli/releases/download/v${VERSION#v}/rush-x86_64-linux.zip"
fi

archive="$(mktemp)"
curl --fail --location --silent --show-error -o "$archive" "$url"
mkdir -p "$rush_home"
unzip -oq "$archive" -d "$rush_home"
rm "$archive"
chmod +x "$rush_home/bin/rush"

chown -R "$user" "$rush_home"
su "$user" -c "RUSH_HOME=$rush_home $rush_home/bin/rush --no-color deps sync --dev-deps"

getent group rush >/dev/null || groupadd --system rush
usermod --append --groups rush "$user"
chown -R "$user:rush" "$rush_home"
chmod -R g+rwX "$rush_home"
find "$rush_home" -type d -exec chmod g+s {} +
