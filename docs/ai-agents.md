# AI agents

Rush projects are ready for AI coding agents such as Claude Code, Codex, Cursor, Copilot
and Gemini. `rush create` adds three files:

| File | Purpose |
|---|---|
| `AGENTS.md` | Instructions every agent reads: the workflow, the rules that matter most, and your own notes about the project. |
| `CLAUDE.md` | Contains `@AGENTS.md`, so Claude Code reads the same instructions. |
| `.claude/skills/rush/SKILL.md` | Everything an agent needs to write a correct extension: blocks, types, dropdowns, events, asynchronous functions, the manifest, dependencies, resources and common errors. Claude Code loads it when it's relevant, and `AGENTS.md` points other agents to it. |

The workflow they teach is the one to follow by hand too: change the code, run
`rush build` and fix what it reports, then read `out/<package>.md` to check that the
blocks are the ones intended. `rush build` can't run the extension, so agents are told to
say what still needs testing in App Inventor.

## Keeping them up to date

```sh
rush agents
```

`rush agents` rewrites the skill for the installed Rush version. It also adds
`AGENTS.md` and `CLAUDE.md` when they are missing, which is how projects created before
Rush 2.3 get them. It never changes an existing `AGENTS.md` or `CLAUDE.md`: they belong
to you, so add your project's conventions under **Project notes**.

Run it after `rush upgrade`.

## Documentation for AI tools

[`llms.txt`](llms.txt) lists these pages for AI tools that read documentation from the
web.
