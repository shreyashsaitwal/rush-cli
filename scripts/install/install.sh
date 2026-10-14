#!/usr/bin/env bash
set -euo pipefail

repo="shreyashsaitwal/rush-cli"

if ! command -v unzip >/dev/null; then
  echo 'err: `unzip` is required to install Rush. Please install it and try again.' >&2
  exit 1
fi

if [ -n "${RUSH_HOME:-}" ]; then
  rush_home="$RUSH_HOME"
elif command -v rush >/dev/null; then
  rush_home="$(dirname "$(dirname "$(command -v rush)")")"
else
  rush_home="$HOME/.rush"
fi

case "$(uname -sm)" in
  "Darwin x86_64") target="x86_64-apple-darwin" ;;
  "Darwin arm64") target="arm64-apple-darwin" ;;
  "Linux x86_64") target="x86_64-linux" ;;
  *)
    echo "err: Unsupported platform: $(uname -sm)" >&2
    exit 1
    ;;
esac

mkdir -p "$rush_home"
archive="$rush_home/rush-$target.zip"
curl --fail --location --progress-bar -o "$archive" \
  "https://github.com/$repo/releases/latest/download/rush-$target.zip"
unzip -oq "$archive" -d "$rush_home"
rm "$archive"
chmod +x "$rush_home/bin/rush"

echo
echo "Installed the Rush CLI at $rush_home/bin/rush"
echo "Rush now needs the App Inventor runtime and build tools (about 140 MB)."
read -r -p "Download them now? (Y/n) " reply </dev/tty || reply=y
echo

if [[ ! "$reply" =~ ^[Nn]$ ]]; then
  "$rush_home/bin/rush" deps sync --dev-deps
  echo
  echo "Success! Installed Rush at $rush_home/bin/rush"
else
  echo "Run \`rush deps sync --dev-deps\` before building your first extension."
fi

case "$SHELL" in
  */zsh) shell_profile=".zshrc" ;;
  */bash) shell_profile=".bashrc" ;;
  *) shell_profile=".profile" ;;
esac

echo
echo "Add Rush to your PATH by adding this line to \$HOME/$shell_profile:"
echo "export PATH=\"\$PATH:$rush_home/bin\""
echo
echo 'Then run `rush --help` to get started.'
