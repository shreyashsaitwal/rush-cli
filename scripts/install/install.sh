#!/bin/bash

# Exit immediately if any command exits with non-zero exit status.
set -e

if ! command -v unzip &> /dev/null; then
	echo "err: unzip is required to install Rush. Please install it and try again."
	exit 1
fi

# Check if Rush is already installed; if it is, use the old
# path for storing Rush executable
if ! command -v rush &> /dev/null; then
  binDir="$HOME/.rush/bin"
  if [ ! -d "$binDir" ]; then
    mkdir $binDir
  fi
else
  binDir="$(dirname $(which rush))"
fi

# Set the target
if [ "$OS" = "Windows_NT" ]; then
  target='win'
else
  case $(uname -sm) in
    "Darwin x86_64" | "Darwin arm64")
      target="mac" ;;
    *)
      target="linux" ;;
  esac
fi

zipUrl="https://github.com/shreyashsaitwal/rush-cli/releases/latest/download/rush-$target.zip"

# Download and unzip rush-$target.zip
curl --location --progress-bar -o "$binDir/rush-$target.zip" "$zipUrl"
unzip -oq "$binDir/rush-$target.zip" -d $binDir/
rm "$binDir/rush-$target.zip"

if [ "$OS" = "Windows_NT" ]; then
  dataDir="$APPDATA/rush"
else
  case $(uname -sm) in
    "Darwin x86_64" | "Darwin arm64")
      dataDir="$HOME/Library/Application Support/rush" ;;
    *)
      dataDir="home/$HOME/rush" ;;
  esac
fi

# Delete dataDir if it already exists
if [ -d $dataDir ]; then
  rm -rf $dataDir
fi

# Then (re-)create it
mkdir $dataDir

# Move the EXEs under the binDir
mv "$binDir/exe/$target/*" $binDir
chmod +x "$binDir/rush"

rm -r "$binDir/exe/"

# Move all the directories that were unzipped
mv $(ls -d "$binDir/*/") $dataDir

echo "Success! Installed Rush at $binDir/rush"
if command -v rush &> /dev/null; then
  echo "Run 'rush --help' to get started."
else
  case $SHELL in
    /bin/zsh) shell_profile=".zshrc" ;;
    *) shell_profile=".bash_profile" ;;
	esac
	echo "Now, manually add the directory to your \$HOME/$shell_profile (or similar):"
	echo "  export PATH=\"\$binDir:\$PATH\""
	echo "Run 'rush --help' to get started."
fi
