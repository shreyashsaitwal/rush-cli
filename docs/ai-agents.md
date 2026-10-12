# AI agents

Rush projects are ready for AI coding agents such as Claude Code, Codex, Cursor, Copilot
and Gemini. `rush create` adds the instructions they follow:

| File | Purpose |
|---|---|
| `AGENTS.md` | Instructions every agent reads: the workflow, the rules that matter most, and your own notes about the project. |
| `CLAUDE.md` | Contains `@AGENTS.md`, so Claude Code reads the same instructions. |
| `.claude/skills/rush/SKILL.md` | Everything an agent needs to write a correct extension: blocks, types, dropdowns, events, asynchronous functions, the manifest, dependencies, resources and common errors. Claude Code loads it when it's relevant, and `AGENTS.md` points other agents to it. |

The workflow they teach is the one to follow by hand too: change the code, run
`rush build` and fix what it reports, then read `out/<package>.md` to check that the
blocks are the ones intended. `rush build` can't run the extension, so agents are told to
say what still needs testing in App Inventor.

## Where agents work

Agents need Rush and a JDK to run `rush build`. Rush projects come with both set up:

| File | Purpose |
|---|---|
| `.devcontainer/devcontainer.json` | A [dev container](dev-containers.md) with Rush and JDK 17, for GitHub Codespaces and VS Code. Agents running in it, such as Copilot in VS Code, can build the extension straight away. |
| `.github/workflows/copilot-setup-steps.yml` | Installs Rush and the project's dependencies before [GitHub Copilot's cloud agent](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/cloud-agent) starts working on an issue. |

On your own computer, agents use the Rush you installed.

## Keeping them up to date

```sh
rush agents
```

`rush agents` rewrites the skill for the installed Rush version. It also adds the other
files above when they are missing, which is how older projects get them. It never changes
them once they exist: they belong to you, so add your project's conventions to
`AGENTS.md` under **Project notes**.

Run it after `rush upgrade`.

## Documentation for AI tools

[`llms.txt`](llms.txt) lists these pages for AI tools that read documentation from the
web.
