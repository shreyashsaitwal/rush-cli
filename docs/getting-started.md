# Getting started

## Requirements

Rush needs a JDK, version 17 or newer, either on your `PATH` or pointed to by `JAVA_HOME`.
A JRE isn't enough: Rush runs `javac`, and ProGuard reads the JDK's `jmods`.

## Installation

On Linux and macOS:

```sh
curl -fsSL https://raw.githubusercontent.com/zainulhassan815/rush-cli/main/scripts/install/install.sh | bash
```

On Windows, in PowerShell:

```ps1
iwr https://raw.githubusercontent.com/zainulhassan815/rush-cli/main/scripts/install/install.ps1 -useb | iex
```

The installer puts Rush in `~/.rush` (`%UserProfile%\.rush` on Windows) and offers to
download the App Inventor runtime and build tools, about 140 MB. Add `~/.rush/bin` to your
`PATH` as it suggests, then check the installation:

```sh
rush --version
```

Run `rush upgrade` later to install new releases.

## Creating a project

```sh
rush create counter --package com.example --language java --ide intellij
```

This creates a `counter` directory with an extension in the package `com.example.counter`.
Rush appends the project name to the package unless it already ends with it. Without the
options, `rush create` asks for them.

```
counter/
├── rush.yml                  project configuration
├── src/
│   ├── AndroidManifest.xml   manifest entries the extension adds to apps
│   ├── proguard-rules.pro    rules for rush build --optimize
│   └── com/example/counter/
│       └── Counter.java      the extension
├── assets/
│   └── icon.png              the extension's icon
├── deps/                     local JAR and AAR libraries
├── .github/workflows/
│   └── build.yml             builds and releases the extension on GitHub
├── AGENTS.md                 instructions for AI coding agents
├── CLAUDE.md
└── .claude/skills/rush/
    └── SKILL.md              how to write extensions, for AI agents
```

`--ide` generates project files for IntelliJ IDEA and Android Studio (`intellij`), for
Eclipse and VS Code (`eclipse`), or for both. They put App Inventor's runtime and the
project's dependencies on the editor's classpath, so code completion works.

## Building

```sh
cd counter
rush build
```

The extension is written to `out/com.example.counter.aix`, along with
`out/com.example.counter.md`, a Markdown reference of its blocks.

## Using the extension

In App Inventor, open the **Extension** palette, choose **Import extension** and upload
the `.aix` file. The extension appears in the palette and can be dragged onto a screen
like any non-visible component.

The AI Companion can load most extensions directly. Extensions that ship AARs, which
includes extensions with [resources](resources.md) and some
[dependencies](dependencies.md#how-libraries-are-shipped), only work in built apps: test
those with **Build → Android App (.apk)**.

Next, see [writing extensions](writing-extensions.md). To work with an AI coding agent,
see [AI agents](ai-agents.md).
