import 'dart:io' show Directory, File, exit;

import 'package:dart_console/dart_console.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/commands/rush_command.dart';
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

class CreateCommand extends RushCommand {
  final FileService _fs;

  CreateCommand(this._fs) {
    argParser
      ..addOption('org',
          abbr: 'o',
          help:
              'The organization name in reverse domain name notation. This is used as extension\'s package name.')
      ..addOption('lang',
          abbr: 'l',
          help:
              'The language in which the extension\'s starter template should be generated',
          allowed: ['Java', 'Kotlin', 'java', 'kotlin', 'J', 'K', 'j', 'k']);
  }

  @override
  String get description =>
      'Scaffolds a new extension project in the current working directory.';

  @override
  String get name => 'create';

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

    final kebabCasedName = Casing.kebabCase(name);
    final projectDir = p.join(_fs.cwd, kebabCasedName);

    if (Directory(projectDir).existsSync() &&
        Directory(projectDir).listSync().isNotEmpty) {
      Logger.log(LogType.erro,
          'Cannot create "$projectDir" because it already exists and is not empty.');
      exit(1);
    }

    final prompt = RushPrompt(questions: _questions());

    var orgName =
        (argResults!['org'] ?? prompt.askQuestionAt('org').last) as String;
    final lang =
        (argResults!['lang'] ?? prompt.askQuestionAt('lang').last) as String;

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

    final extPath = p.joinAll([projectDir, 'src', ...orgName.split('.')]);
    final ideaDir = p.join(projectDir, '.idea');

    final filesToCreate = {
      if (['j', 'java'].contains(lang.toLowerCase()))
        p.join(extPath, '$pascalCasedName.java'): getExtensionTempJava(
          pascalCasedName,
          orgName,
        )
      else
        p.join(extPath, '$pascalCasedName.kt'): getExtensionTempKt(
          pascalCasedName,
          orgName,
        ),
      p.join(projectDir, 'src', 'AndroidManifest.xml'): getManifestXml(orgName),
      p.join(projectDir, 'src', 'proguard-rules.pro'):
          getPgRules(orgName, pascalCasedName),
      p.join(projectDir, 'rush.yml'):
          getRushYamlTemp(pascalCasedName, lang == 'Kotlin'),
      p.join(projectDir, 'README.md'): getReadme(pascalCasedName),
      p.join(projectDir, '.gitignore'): getDotGitignore(),
      p.join(projectDir, 'deps', '.placeholder'):
          'This directory stores your extension\'s dependencies.',

      // IntelliJ IDEA files
      p.join(ideaDir, 'misc.xml'): getMiscXml(),
      p.join(ideaDir, 'libraries', 'dev-deps.xml'): getDevDepsXml(_fs.dataDir),
      p.join(ideaDir, 'libraries', 'deps.xml'): getDepsXml(),
      p.join(ideaDir, 'modules.xml'): getModulesXml(kebabCasedName),
      p.join(ideaDir, '$kebabCasedName.iml'):
          getIml(ideaDir, ['dev-deps', 'deps'])
    };

    // Creates the required files for the extension.
    try {
      filesToCreate.forEach((path, contents) {
        CmdUtils.writeFile(path, contents);
      });

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
