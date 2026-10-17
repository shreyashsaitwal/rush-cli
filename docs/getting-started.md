# Getting started

## Without installing anything

The [Rush extension template](https://github.com/zainulhassan815/rush-extension-template) creates a project on GitHub, in the
browser:

1. Click **Use this template** → **Create a new repository**.
2. In the new repository's **Actions** tab, run **Create extension** with the extension's
   name, a package name and the language. It commits the project and starts a build.
3. Open the repository in a [codespace](dev-containers.md): **Code** → **Codespaces** →
   **Create codespace on main**.

The rest of this page sets Rush up on your own computer.

## Requirements

Rush needs a JDK, version 17 or newer, either on your `PATH` or pointed to by `JAVA_HOME`.
A JRE isn't enough: Rush runs `javac`, and R8 reads classes from the JDK's `jmods`.

## Installation

On Linux and macOS:

```sh
curl -fsSL https://raw.githubusercontent.com/shreyashsaitwal/rush-cli/main/scripts/install/install.sh | bash
```

On Windows, in PowerShell:

```ps1
iwr https://raw.githubusercontent.com/shreyashsaitwal/rush-cli/main/scripts/install/install.ps1 -useb | iex
```

The installer puts Rush in `~/.local/share/rush` on Linux and macOS (or `$XDG_DATA_HOME/rush`
if that env var is set), and `%LOCALAPPDATA%\\rush` on Windows. It offers to download the App
Inventor runtime and build tools (about 140 MB). Add the `bin` subdirectory to your `PATH` as
it suggests, then check the installation:

```sh
rush --version
```

Run `rush upgrade` later to install new releases.

To install a specific release, such as a beta, set `RUSH_VERSION` for the installer:

```sh
curl -fsSL https://raw.githubusercontent.com/shreyashsaitwal/rush-cli/main/scripts/install/install.sh | RUSH_VERSION=2.1.0-beta.1 bash
```

```ps1
$env:RUSH_VERSION = "2.1.0-beta.1"; iwr https://raw.githubusercontent.com/shreyashsaitwal/rush-cli/main/scripts/install/install.ps1 -useb | iex
```

`rush upgrade` only installs stable releases, so reinstall this way to move to a newer beta.

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
│   ├── build.yml             builds and releases the extension on GitHub
│   └── copilot-setup-steps.yml  prepares GitHub Copilot's cloud agent
├── .devcontainer/
│   └── devcontainer.json     a ready-made environment for Codespaces and VS Code
├── .project, .classpath      project files for VS Code and Eclipse
├── AGENTS.md                 instructions for AI coding agents
├── CLAUDE.md
└── .claude/skills/rush/
    └── SKILL.md              how to write extensions, for AI agents
```

Project files put App Inventor's runtime and the project's dependencies on the editor's
classpath, so code completion works. Every project gets them for VS Code and Eclipse
(`.project` and `.classpath`). `--ide intellij` or `--ide both` adds them for IntelliJ IDEA
and Android Studio. `.classpath` and `.idea/libraries/` hold paths on your computer, so
they aren't committed: `rush deps sync` and `rush build` write them.

The project can also be opened in a [dev container](dev-containers.md), in GitHub
Codespaces or in VS Code, without installing anything.

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
