# Commands

Run `rush help <command>` for a command's options.

## rush create

```sh
rush create <name> [--package <package>] [--language java|kotlin] [--ide intellij|eclipse|both]
```

Creates a project in a new `<name>` directory. The extension's package is `--package`
followed by the project name, unless it already ends with it. Rush asks for missing
options in a terminal, and fails without them in scripts. See
[Getting started](getting-started.md#creating-a-project).

## rush agents

Adds or updates the instructions AI coding agents follow in the project. See
[AI agents](ai-agents.md).

## rush build

```sh
rush build [--optimize]
```

Builds the extension into `out`. `--optimize` (`-o`) shrinks, optimizes and obfuscates
it with ProGuard. See [Building](building.md).

## rush clean

Deletes the project's build files and caches in `.rush`.

## rush deps sync

```sh
rush deps sync [--dev-deps] [--project-deps] [--force]
```

Downloads what builds need: the App Inventor runtime and build tools (dev dependencies,
shared by all projects) and the project's dependencies. `rush build` does this on its
own when something is missing or `rush.yml` changed.

| Option | |
|---|---|
| `-d`, `--dev-deps` | Only the runtime and build tools |
| `-p`, `--project-deps` | Only the project's dependencies |
| `-f`, `--force` | Re-resolve everything, even if up to date |

Outside a project it syncs only the dev dependencies. It also updates the IntelliJ and
Eclipse project files with the resolved libraries.

## rush deps tree

Prints the project's resolved dependency tree. A subtree printed earlier is marked `*`.

## rush migrate

Converts a Rush 1 project in the current directory to Rush 2. See
[Migrating from Rush 1](migrating.md).

## rush upgrade

```sh
rush upgrade [--force] [--access-token <token>]
```

Installs the latest Rush release. `--force` reinstalls even when Rush is up to date.
`--access-token` passes a GitHub token, which is only needed if GitHub's API rate limit
is hit.

## Global options

| Option | |
|---|---|
| `-v`, `--verbose` | Prints debug logs, such as the details of a failed build |
| `-c`, `--[no-]color` | Colors the output. It's on in terminals that support it, and off when the output is redirected or `NO_COLOR` is set |
| `-V`, `--version` | Prints Rush's version |

## Environment variables

| Variable | |
|---|---|
| `RUSH_HOME` | Where Rush is installed, `~/.rush` by default |
| `JAVA_HOME` | The JDK to use. Otherwise `java` and `javac` are taken from `PATH` |
| `M2_HOME` | The local Maven repository is `$M2_HOME/repository` instead of `~/.m2/repository` |
| `NO_COLOR` | Turns colors off |
| `RUSH_AI2_RUNTIME_ZIP` | Installs the App Inventor runtime from a local copy of its release archive instead of downloading it |
