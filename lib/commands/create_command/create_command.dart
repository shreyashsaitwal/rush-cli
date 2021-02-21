import 'dart:io' show Directory, File, Platform, exit;

import 'package:args/command_runner.dart';
import 'package:dart_console/dart_console.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

import 'package:rush_prompt/rush_prompt.dart';

import 'package:rush_cli/commands/create_command/casing.dart';
import 'package:rush_cli/commands/create_command/questions.dart';
import 'package:rush_cli/mixins/copy_mixin.dart';
import 'package:rush_cli/templates/android_manifest.dart';
import 'package:rush_cli/templates/dot_classpath_template.dart';
import 'package:rush_cli/templates/dot_gitignore.dart';
import 'package:rush_cli/templates/dot_proj_template.dart';
import 'package:rush_cli/templates/readme.dart';
import 'package:rush_cli/templates/rush_yaml_template.dart';
import 'package:rush_cli/templates/extension_template.dart';

class CreateCommand extends Command with CopyMixin {
  final String _cd;
  String extName;

  CreateCommand(this._cd);

  @override
  String get description =>
      'Scaffolds a new extension project in the current working directory.';

  @override
  String get name => 'create';

  @override
  void printUsage() {
    PrintArt();

    Console()
      ..setForegroundColor(ConsoleColor.cyan)
      ..write(' create: ')
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..writeLine(description)
      ..writeLine()
      ..writeLine(' Usage: ')
      ..setForegroundColor(ConsoleColor.brightBlue)
      ..write('   rush ')
      ..setForegroundColor(ConsoleColor.cyan)
      ..write('create ')
      ..resetColorAttributes()
      ..writeLine('[extension_name]');
  }

  /// Creates a new extension project in the current directory.
  @override
  Future<void> run() async {
    String name;
    if (argResults.rest.length == 1) {
      name = argResults.rest.first;
    } else {
      printUsage();
      exit(64); // Exit code 64 indicates usage error
    }

    PrintArt();

    final answers = RushPrompt(questions: Questions.questions).askAll();
    final authorName = answers[1][1].toString().trim();
    final versionName = answers[2][1].toString().trim();
    var orgName = answers[0][1].toString().trim();

    final camelCasedName = Casing.camelCase(name);
    final pascalCasedName = Casing.pascalCase(name);
    final kebabCasedName = Casing.kebabCase(name);

    // If the last word after '.' in pacakge name is same as the
    // extension name, then
    final isOrgAndNameSame = orgName.split('.').last == camelCasedName;
    if (!isOrgAndNameSame) {
      orgName = orgName + '.' + camelCasedName;
    }

    final projectDir = p.join(_cd, kebabCasedName);

    // Creates the required files for the extension.
    try {
      final extPath = p.joinAll([projectDir, 'src', ...orgName.split('.')]);
      _writeFile(
          p.join(extPath, '$pascalCasedName.java'),
          getExtensionTemp(
            pascalCasedName,
            orgName,
          ));

      _writeFile(p.join(projectDir, 'src', 'AndroidManifest.xml'),
          getManifestXml(orgName));

      _writeFile(p.join(projectDir, 'rush.yml'),
          getRushYaml(pascalCasedName, versionName, authorName));

      _writeFile(p.join(projectDir, 'README.md'), getReadme(pascalCasedName));
      _writeFile(p.join(projectDir, '.gitignore'), getDotGitignore());
      _writeFile(p.join(projectDir, 'deps', '.placeholder'),
          'This directory stores your extension\'s depenedencies.');

      // These files help Eclipse Java based IDE's to analyze the project and
      // provide features like code completion.
      _writeFile(p.join(projectDir, '.classpath'), getDotClasspath());
      _writeFile(p.join(projectDir, '.project'), getDotProject(camelCasedName));
      _writeFile(p.join(projectDir, '.settings', 'org.eclipse.jdt.core.prefs'),
          'eclipse.preferences.version=1\norg.eclipse.jdt.core.compiler.problem.enablePreviewFeatures=disabled\n');
    } catch (e) {
      ThrowError(message: 'ERR ' + e.toString());
    }

    try {
      Directory(p.join(projectDir, '.rush', 'dev_deps'))
          .createSync(recursive: true);
      Directory(p.join(projectDir, 'assets')).createSync(recursive: true);
    } catch (e) {
      ThrowError(message: 'ERR ' + e.toString());
    }

    Hive.init(p.join(projectDir, '.rush'));
    var box = await Hive.openBox('data');
    await box.putAll({
      'version': 1,
      'org': orgName,
      'rushYmlLastMod': DateTime.now(),
      'srcDirLastMod': DateTime.now(),
    });

    // Copy dev-deps.
    final baseDir = Platform.script.toFilePath(windows: Platform.isWindows);
    final devDepsDir = p.join(baseDir.split('bin').first, 'dev-deps');
    copyDir(Directory(devDepsDir),
        Directory(p.join(projectDir, '.rush', 'dev_deps')));

    exit(0);
  }

  /// Creates a file in [path] and writes [content] inside it.
  void _writeFile(String path, String content) {
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }
}
