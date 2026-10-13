import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:rush/src/agents/skill.dart';
import 'package:rush/src/commands/create/templates/eclipse_files.dart';
import 'package:rush/src/utils/file_extension.dart';

const _skillPath = '.claude/skills/rush/SKILL.md';

const _agentsMd = '''
# Agent instructions

This is an MIT App Inventor extension built with Rush.

Before changing the extension, read `$_skillPath`.
It explains how blocks, dropdowns, events, dependencies and resources work,
and the limits App Inventor imposes.

## Workflow

1. Run `rush build` after every change and fix every error it reports.
2. Read `out/<package>.md` to check that the blocks match what was asked.
3. Tell the user what to test in App Inventor: `rush build` can't run the
   extension.

## Rules

- Blocks are public methods of the `@Extension` class, annotated with
  `@SimpleFunction`, `@SimpleProperty` or `@SimpleEvent`. Use primitive
  types.
- Extensions are non-visible. To show a view, add it to an arrangement passed
  to a block.
- Dropdown enums go in a directory named `helpers`.
- Fire events on the main thread, never while `Screen.Initialize` runs.
- Declare every library in `rush.yml`.
- Don't edit `.rush/` or `out/`: Rush generates them.

## Project notes

Add conventions specific to this project here.
''';

const _claudeMd = '@AGENTS.md\n';

const _devcontainerJson = '''
{
  "name": "Rush",
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu-24.04",
  "features": {
    "ghcr.io/zainulhassan815/rush-cli/rush:1": {}
  },
  "postCreateCommand": "rush deps sync",
  "customizations": {
    "vscode": {
      "extensions": ["GitHub.copilot-chat"]
    }
  }
}
''';

const _copilotSetupSteps = '''
name: Copilot setup steps

on:
  workflow_dispatch:
  push:
    paths:
      - .github/workflows/copilot-setup-steps.yml
  pull_request:
    paths:
      - .github/workflows/copilot-setup-steps.yml

jobs:
  copilot-setup-steps:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v7
      - uses: zainulhassan815/rush-cli@v2
      - run: rush deps sync
''';

Map<String, String> _agentFiles(String projectDir) => {
      'AGENTS.md': _agentsMd,
      'CLAUDE.md': _claudeMd,
      _skillPath: rushSkill,
      '.devcontainer/devcontainer.json': _devcontainerJson,
      '.github/workflows/copilot-setup-steps.yml': _copilotSetupSteps,
      '.project': dotProject(p.basename(projectDir)),
    };

Future<List<String>> writeAgentFiles(String projectDir) async {
  final written = <String>[];
  for (final MapEntry(key: path, value: contents)
      in _agentFiles(projectDir).entries) {
    final file = p.join(projectDir, path);
    if (path == _skillPath || !await file.asFile().exists()) {
      await file.asFile(true).writeAsString(contents);
      written.add(path);
    }
  }
  await _ignoreMachinePaths(projectDir);
  return written;
}

Future<void> _ignoreMachinePaths(String projectDir) async {
  final gitignore = p.join(projectDir, '.gitignore').asFile();
  if (!await gitignore.exists()) {
    return;
  }
  final contents = await gitignore.readAsString();
  final lines = contents.split('\n');
  final missing = [
    '/.classpath',
    if (await p.join(projectDir, '.idea').asDir().exists()) '/.idea/libraries/',
  ].where((path) => !lines.contains(path));
  if (missing.isNotEmpty) {
    final separator = contents.isEmpty || contents.endsWith('\n') ? '' : '\n';
    await gitignore.writeAsString('$separator${missing.join('\n')}\n',
        mode: FileMode.append);
  }
}
