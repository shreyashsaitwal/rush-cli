# ⚡ Rush

**Rush** is a modern extension builder for MIT App Inventor 2.

This is a maintained fork of [shreyashsaitwal/rush-cli](https://github.com/shreyashsaitwal/rush-cli),
created by Shreyash Saitwal, which brings Rush 2.0 to a stable release.

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
* Optional shrinking and obfuscation with ProGuard
* Markdown documentation of every block and dropdown, generated with each build
* Android resources (layouts, drawables, strings…) shipped with the extension

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

## Resources

Put Android resources such as layouts, drawables, strings and colors in a `res` directory
next to `src`, laid out as in any Android project. Rush validates them, ships them in an
AAR inside the AIX, and generates the `R` class in your extension's package:

```java
View card = LayoutInflater.from(form).inflate(R.layout.com_example_myext_card, parent, false);
```

Every resource name except IDs must start with the extension package, with dots replaced
by underscores (`com_example_myext_` for `com.example.myext`). All resources of an app
share one namespace, so this keeps extensions from overriding each other's resources or
App Inventor's.

Resources can reference each other and Android's own resources (`@android:color/white`,
`?android:attr/colorAccent`), but not those of AppCompat or other AndroidX libraries.
Like any extension that ships AARs, these extensions work in built apps but not in the AI
Companion.

## GitHub Actions

Workflows can install Rush with the setup action, which also caches the App Inventor
runtime and Maven dependencies:

```yaml
- uses: zainulhassan815/rush-cli@v2
  with:
    version: 2.2.0 # optional, defaults to the latest release
- run: rush build
```

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
