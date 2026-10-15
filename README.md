# ⚡ Rush

**Rush** is a modern extension builder for MIT App Inventor 2.

## Features

* Kotlin and Java support, with Java 17 language features (records, switch expressions,
  text blocks…) desugared automatically
* Newer Java APIs such as `java.time` work on older Android versions when `min_sdk` is 24
  or higher, using Google's backport library, trimmed to what the extension uses
* Maven dependency management, resolved from Maven Central and Google's Maven repository
* **AARs with resources:** AAR dependencies are shipped as-is, so App Inventor compiles
  their layouts, drawables and styles and generates their `R` classes
* `AndroidManifest.xml` support, merged with the manifests of AAR dependencies
* Builds against the latest App Inventor release (currently **v206**)
* Optional shrinking and obfuscation with R8
* Markdown documentation of every block and dropdown, generated with each build
* Android resources (layouts, drawables, strings…) shipped with the extension
* Ready for AI coding agents: new projects include instructions that teach them to write,
  build and check extensions
* Build in GitHub Codespaces or a dev container, with nothing to install

See the [roadmap](ROADMAP.md) for everything that's supported and planned.

## Start in your browser

To make an extension without installing anything, create a repository from the
[Rush extension template](https://github.com/zainulhassan815/rush-extension-template). A workflow creates the project, and a
codespace gives you VS Code, Rush and GitHub Copilot in the browser.

## Installation

Rush requires JDK 17 or newer.

### Linux and macOS

```sh
curl -fsSL https://raw.githubusercontent.com/shreyashsaitwal/rush-cli/main/scripts/install/install.sh | bash
```

Then add `$HOME/.local/share/rush/bin` to your `PATH`.

### Windows

In PowerShell, run:

```ps1
iwr https://raw.githubusercontent.com/shreyashsaitwal/rush-cli/main/scripts/install/install.ps1 -useb | iex
```

## Quick start

```sh
rush create my_extension --package com.example --language kotlin --ide intellij
cd my_extension
rush build
```

The extension (AIX) is generated in the `out` directory. Continue with
[getting started](docs/getting-started.md).

## Documentation

The [documentation](docs/README.md) covers writing extensions, dependencies, resources,
building, GitHub Actions and migrating from Rush 1, with a reference of `rush.yml`, the
commands and common errors.

## Building Rush

```sh
dart pub get
dart run build_runner build
dart compile exe bin/rush.dart -o build/rush

cd processor && ./gradlew build :processor:shadowJar
```

The App Inventor runtime bundle is built with `ai2/build-runtime.sh <ai2-tag>`, or by the
*App Inventor runtime* workflow, which publishes it as a release asset.
