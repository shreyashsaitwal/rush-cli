# ⚡ Rush

**Rush** is a modern extension builder for MIT App Inventor 2.

This is a maintained fork of [shreyashsaitwal/rush-cli](https://github.com/shreyashsaitwal/rush-cli),
created by Shreyash Saitwal, which brings Rush 2.0 to a stable release.

## Features

* Kotlin and Java support, with Java 8+ language features desugared automatically
* Maven dependency management, resolved from Maven Central and Google's Maven repository
* **AARs with resources:** AAR dependencies are shipped as-is, so App Inventor compiles
  their layouts, drawables and styles and generates their `R` classes
* `AndroidManifest.xml` support, merged with the manifests of AAR dependencies
* Builds against the latest App Inventor release (currently **v206**)
* Optional shrinking and obfuscation with ProGuard
* Markdown documentation of every block and dropdown, generated with each build

See the [roadmap](ROADMAP.md) for everything that's supported and planned.

## Installation

Rush requires JDK 17 or newer.

### Linux and macOS

```sh
curl -fsSL https://raw.githubusercontent.com/zainulhassan815/rush-cli/main/scripts/install/install.sh | bash
```

Then add `$HOME/.rush/bin` to your `PATH`.

### Windows

In PowerShell, run:

```ps1
iwr https://raw.githubusercontent.com/zainulhassan815/rush-cli/main/scripts/install/install.ps1 -useb | iex
```

## Quick start

```sh
rush create my_extension --package com.example --language kotlin --ide intellij
cd my_extension
rush build
```

The extension (AIX) is generated in the `out` directory. Run `rush build --optimize` to
shrink and obfuscate it with ProGuard.

## Dependencies

Declare dependencies in `rush.yml` as Maven coordinates or as JAR/AAR files stored in
the `deps` directory:

```yaml
dependencies:
- org.jetbrains.kotlin:kotlin-stdlib:2.4.20
- androidx.media3:media3-ui:1.11.1
- my-library.aar
```

Run `rush deps sync` after changing them, and `rush deps tree` to inspect the resolved
dependency tree.

Libraries App Inventor already provides, such as AndroidX `appcompat` or Guava, are never
bundled. Rush warns when a dependency needs a newer version of such a library than App
Inventor provides, as App Inventor's version is used at runtime.

## Configuration

`rush.yml` is described by the [JSON schema](schema/rush.yml) in this repository.

## Building Rush

```sh
dart pub get
dart run build_runner build
dart compile exe bin/rush.dart -o build/rush

cd processor && ./gradlew build :processor:shadowJar
```

The App Inventor runtime bundle is built with `ai2/build-runtime.sh <ai2-tag>`, or by the
*App Inventor runtime* workflow, which publishes it as a release asset.
