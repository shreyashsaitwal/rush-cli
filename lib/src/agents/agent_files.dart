import 'package:path/path.dart' as p;

import 'package:rush/src/agents/skill.dart';
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
- Dropdown enums go in a directory named `helpers`.
- Fire events on the main thread, never while `Screen.Initialize` runs.
- Declare every library in `rush.yml`.
- Don't edit `.rush/` or `out/`: Rush generates them.

## Project notes

Add conventions specific to this project here.
''';

const _claudeMd = '@AGENTS.md\n';

Map<String, String> _agentFiles() => {
      'AGENTS.md': _agentsMd,
      'CLAUDE.md': _claudeMd,
      _skillPath: rushSkill,
    };

Future<List<String>> writeAgentFiles(String projectDir) async {
  final written = <String>[];
  for (final MapEntry(key: path, value: contents) in _agentFiles().entries) {
    final file = p.join(projectDir, path);
    if (path == _skillPath || !await file.asFile().exists()) {
      await file.asFile(true).writeAsString(contents);
      written.add(path);
    }
  }
  return written;
}
