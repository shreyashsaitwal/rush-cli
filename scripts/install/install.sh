#!/bin/sh

# Exit immediately if any command exits with non-zero exit status.
set -e

if ! command -v unzip >/dev/null; then
	echo "err: unzip is required to install Rush. Please install it and try again"
	exit 1
fi

# Check if Rush is already installed; if it is, use the old path for storing,
# Rush executable
if ! command -v rush >/dev/null; then
  binDir="$HOME/.rush/bin"
  if [ ! -d "$binDir" ]; then
    mkdir -p "$binDir"
  fi
else
  binDir="$(dirname $(which rush))"
fi

# Set the target and data dir
if [ "$OS" = "Windows_NT" ]; then
  target="win"
  dataDir="$APPDATA/rush"
else
  case $(uname -sm) in
  "Darwin x86_64")
    target="mac"
    dataDir="$HOME/Library/Application Support/rush"
    ;;
  *)
    target="linux"
    dataDir="$HOME/rush"
    ;;
  esac
fi

zipUrl="https://github.com/shreyashsaitwal/rush-cli/releases/latest/download/rush-$target.zip"

# Download and unzip rush-$target.zip
curl --location --progress-bar -o "$binDir/rush-$target.zip" "$zipUrl"
unzip -oq "$binDir/rush-$target.zip" -d $binDir/
rm "$binDir/rush-$target.zip"

# Delete dataDir if it already exists
if [ -d "$dataDir" ]; then
  rm -rf "$dataDir"
fi

# Then (re-)create it
mkdir "$dataDir"

# Move the EXEs under the binDir
mv "$binDir/exe/$target"/* "$binDir"
rm -r "$binDir/exe/"

# Move all the directories that were unzipped
mv $(ls -d "$binDir"/*/) "$dataDir"

# Give all the necessary scripts execution permission
chmod +x "$binDir/rush"
chmod +x "$dataDir/tools/kotlinc/bin/kotlinc"
chmod +x "$dataDir/tools/kotlinc/bin/kapt"
chmod +x "$dataDir/tools/jetifier-standalone/bin/jetifier-standalone"

echo
echo "Success! Installed Rush at $binDir/rush"
if ! command -v rush >/dev/null; then
  if [ "$OS" = "Windows_NT" ]; then
    exp=" $dataDir/bin "
    echo
    echo "Now, add the following entry to your 'PATH' environment variable:"
  else
    case $SHELL in
      /bin/zsh) shell_profile=".zshrc" ;;
      *) shell_profile=".bash_profile" ;;
    esac

    exp=" export PATH=\"\$PATH:$binDir\" "
    echo
    echo "Now, manually add Rush's bin directory to your \$HOME/$shell_profile (or similar):"
  fi

    edge=$(echo " $exp " | sed 's/./-/g')
    echo $edge
    echo "|$exp|"
    echo $edge
fi
echo
echo "Run rush --help to get started."
