# Dev containers

A dev container is a ready-made development environment described in the project's
`.devcontainer/devcontainer.json`. Rush projects come with one that has Rush, JDK 17 and
App Inventor's runtime installed, so the extension builds without installing anything.

## GitHub Codespaces

Push the project to GitHub, then on its page choose **Code**, **Codespaces**, **Create
codespace**. VS Code opens in the browser, and `rush build` works in its terminal. Download
the AIX from `out/` and import it into App Inventor.

Personal GitHub accounts get [120 core hours a month](https://docs.github.com/en/billing/concepts/product-billing/github-codespaces)
for free, which is 60 hours on the smallest machine.

## VS Code

With [Docker](https://www.docker.com) and VS Code's
[Dev Containers](https://code.visualstudio.com/docs/devcontainers/containers) extension
installed, open the project and choose **Reopen in Container**.

## What the container has

- Rush, with `RUSH_HOME` at `/usr/local/rush`, and JDK 17.
- VS Code's Java extensions, set up with App Inventor's runtime and the project's
  dependencies, so code completion works.
- GitHub Copilot. Its agent mode reads `AGENTS.md` and can run `rush build`.

When the container is created, it runs `rush deps sync` to download the project's
dependencies.

## The Rush feature

The container gets Rush from the Rush feature, which any dev container can use:

```json
"features": {
  "ghcr.io/zainulhassan815/rush-cli/rush:1": {}
}
```

| Option | Default | Description |
|---|---|---|
| `version` | `latest` | The Rush version to install, like `2.3.0` |

It also installs JDK 17 with the
[Java feature](https://github.com/devcontainers/features/tree/main/src/java).

## Limits

- The container runs on x86_64 Linux. On Macs with Apple silicon, use Codespaces.
- It can't run Android apps. Test the extension in App Inventor.
- `.classpath` holds paths inside the container. Rush projects don't commit it:
  `rush deps sync` and `rush build` write it.

## Existing projects

`rush agents` adds `.devcontainer/devcontainer.json`, the VS Code project files and the
[GitHub Copilot setup](ai-agents.md#where-agents-work) to projects that don't have them.
