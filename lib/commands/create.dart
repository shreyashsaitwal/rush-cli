import 'dart:io' show Directory, File, exit;

import 'package:args/command_runner.dart';
import 'package:dart_console/dart_console.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/utils/casing.dart';
import 'package:rush_cli/utils/cmd_utils.dart';
import 'package:rush_cli/services/file_service.dart';
import 'package:rush_cli/templates/android_manifest.dart';
import 'package:rush_cli/templates/dot_gitignore.dart';
import 'package:rush_cli/templates/extension_source.dart';
import 'package:rush_cli/templates/intellij_files.dart';
import 'package:rush_cli/templates/readme.dart';
import 'package:rush_cli/templates/rules_pro.dart';
import 'package:rush_cli/templates/rush_yml.dart';
import 'package:rush_prompt/rush_prompt.dart';

class CreateCommand extends Command<void> {
  final FileService _fs;

  CreateCommand(this._fs);

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
      ..write(' create ')
      ..resetColorAttributes()
      ..writeLine(description)
      ..writeLine()
      ..write(' Usage: ')
      ..setForegroundColor(ConsoleColor.brightBlue)
      ..write('rush ')
      ..setForegroundColor(ConsoleColor.cyan)
      ..write('create ')
      ..setForegroundColor(ConsoleColor.yellow)
      ..writeLine('<extension_name>')
      ..resetColorAttributes();
  }

  /// Creates a new extension project in the current directory.
  @override
  Future<void> run() async {
    late String name;
    if (argResults!.rest.length == 1) {
      name = argResults!.rest.first;
    } else {
      printUsage();
      exit(64); // Exit code 64 indicates usage error
    }
    PrintArt();

    final kebabCasedName = Casing.kebabCase(name);
    final projectDir = p.join(_fs.cwd, kebabCasedName);

    if (Directory(projectDir).existsSync()) {
      Logger.log(
          LogType.erro,
          'A directory named "$kebabCasedName" already exists in ${_fs.cwd}. Please '
          'choose a different name for the extension or move to different directory.');
      exit(1);
    }

    final answers = RushPrompt(questions: _questions()).askAll();
    var orgName = answers[0][1].toString().trim();
    final lang = answers[1][1].toString().trim();

    final camelCasedName = Casing.camelCase(name);
    final pascalCasedName = Casing.pascalCase(name);

    // If the last word after '.' in package name is not same as the extension
    // name, then append `.$extName` to orgName.
    final isOrgAndNameSame =
        orgName.split('.').last.toLowerCase() == camelCasedName.toLowerCase();
    if (!isOrgAndNameSame) {
      orgName = orgName.toLowerCase() + '.' + camelCasedName.toLowerCase();
    }

    Logger.logCustom('Getting things ready...',
        prefix: '\n• ', prefixFG: ConsoleColor.yellow);

    // Creates the required files for the extension.
    try {
      final extPath = p.joinAll([projectDir, 'src', ...orgName.split('.')]);

      if (lang == 'Java') {
        CmdUtils.writeFile(
            p.join(extPath, '$pascalCasedName.java'),
            getExtensionTempJava(
              pascalCasedName,
              orgName,
            ));
      } else {
        CmdUtils.writeFile(
            p.join(extPath, '$pascalCasedName.kt'),
            getExtensionTempKt(
              pascalCasedName,
              orgName,
            ));
      }

      CmdUtils.writeFile(p.join(projectDir, 'src', 'AndroidManifest.xml'),
          getManifestXml(orgName));
      CmdUtils.writeFile(p.join(projectDir, 'src', 'proguard-rules.pro'),
          getPgRules(orgName, pascalCasedName));

      CmdUtils.writeFile(p.join(projectDir, 'rush.yml'),
          getRushYamlTemp(pascalCasedName, lang == 'Kotlin'));

      CmdUtils.writeFile(
          p.join(projectDir, 'README.md'), getReadme(pascalCasedName));
      CmdUtils.writeFile(p.join(projectDir, '.gitignore'), getDotGitignore());
      CmdUtils.writeFile(p.join(projectDir, 'deps', '.placeholder'),
          'This directory stores your extension\'s dependencies.');

      // IntelliJ IDEA files
      CmdUtils.writeFile(p.join(projectDir, '.idea', 'misc.xml'), getMiscXml());
      CmdUtils.writeFile(
          p.join(projectDir, '.idea', 'libraries', 'dev-deps.xml'),
          getDevDepsXml(_fs.dataDir));
      CmdUtils.writeFile(
          p.join(projectDir, '.idea', 'libraries', 'deps.xml'), getDepsXml());
      CmdUtils.writeFile(p.join(projectDir, '.idea', 'modules.xml'),
          getModulesXml(kebabCasedName));
      CmdUtils.writeFile(
          p.join(projectDir, '.idea', '$kebabCasedName.iml'), getIml());
    } catch (e) {
      Logger.log(LogType.erro, e.toString());
      exit(1);
    }

    try {
      Directory(p.join(projectDir, 'assets')).createSync(recursive: true);
    } catch (e) {
      Logger.log(LogType.erro, e.toString());
      exit(1);
    }

    // Copy icon
    File(p.join(_fs.toolsDir, 'other', 'icon-rush.png'))
        .copySync(p.join(projectDir, 'assets', 'icon.png'));

    Console()
      ..setForegroundColor(ConsoleColor.green)
      ..write('• ')
      ..setForegroundColor(ConsoleColor.brightGreen)
      ..write('Success! ')
      ..resetColorAttributes()
      ..write('Generated a new AI2 extension project in: ')
      ..setForegroundColor(ConsoleColor.cyan)
      ..writeLine(projectDir)
      ..writeLine()
      ..resetColorAttributes()
      ..write('Next up, \n' + ' ' * 2 + '-')
      ..setForegroundColor(ConsoleColor.yellow)
      ..write(' cd ')
      ..resetColorAttributes()
      ..write('into ')
      ..setForegroundColor(ConsoleColor.brightBlue)
      ..write(kebabCasedName + '/')
      ..resetColorAttributes()
      ..writeLine(', and')
      ..write(' ' * 2 + '- run ')
      ..setForegroundColor(ConsoleColor.brightBlue)
      ..write('rush build ')
      ..resetColorAttributes()
      ..writeLine('to compile your extension.');
  }

  List<Question> _questions() {
    return [
      SimpleQuestion(
        question: 'Organisation (package name)',
        id: 'org',
      ),
      MultipleChoiceQuestion(
        question: 'Language',
        options: ['Java', 'Kotlin'],
        id: 'lang',
      ),
    ];
  }
}
