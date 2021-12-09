import 'dart:io' show Directory, File, exit;

import 'package:args/command_runner.dart';
import 'package:dart_console/dart_console.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/helpers/cmd_utils.dart';
import 'package:rush_cli/templates/rules_pro.dart';

import 'package:rush_prompt/rush_prompt.dart';
import 'package:rush_cli/templates/intellij_files.dart';
import 'package:rush_cli/helpers/casing.dart';
import 'package:rush_cli/templates/android_manifest.dart';
import 'package:rush_cli/templates/dot_gitignore.dart';
import 'package:rush_cli/templates/readme.dart';
import 'package:rush_cli/templates/rush_yml.dart';
import 'package:rush_cli/templates/extension_source.dart';

class CreateCommand extends Command {
  final String _cd;
  final String _dataDir;
  String? extName;

  CreateCommand(this._cd, this._dataDir) {
    argParser
      ..addOption('org',
          abbr: 'o',
          help:
              'The organization name in reverse domain name notation. This is used as extension\'s package name.')
      ..addOption('author',
          abbr: 'a', help: 'The name of the extension\'s author.')
      ..addOption('version',
          abbr: 'v', help: 'The version number/name of the extension.')
      ..addMultiOption(
        'lang',
        abbr: 'l',
        help:
            'The language in which the extension\'s starter template should be generated',
        allowed: ['Java', 'Kotlin'],
      );
  }

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
      ..resetColorAttributes()
      ..writeLine(description)
      ..writeLine()
      ..writeLine(' Usage: ')
      ..setForegroundColor(ConsoleColor.brightBlue)
      ..write('   rush ')
      ..setForegroundColor(ConsoleColor.cyan)
      ..write('create ')
      ..resetColorAttributes()
      ..writeLine('<extension_name>');
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
    final projectDir = p.join(_cd, kebabCasedName);

    if (Directory(projectDir).existsSync()) {
      Logger.log(
          LogType.erro,
          'A directory named "$kebabCasedName" already exists in $_cd. Please '
          'choose a different name for the extension or move to different directory.');
      exit(1);
    }

    String orgName;
    final String authorName;
    final String versionName;
    final String lang;

    if (argResults!['org'] == null) {
      orgName = SimpleQuestion(question: 'Organisation (package name)').ask();
    } else {
      orgName = argResults!['org'].toString().trim();
    }

    if (argResults!['author'] == null) {
      authorName = SimpleQuestion(question: 'Author').ask();
    } else {
      authorName = argResults!['author'].toString().trim();
    }

    if (argResults!['version'] == null) {
      versionName = SimpleQuestion(question: 'Version name').ask();
    } else {
      versionName = argResults!['version'].toString().trim();
    }

    if ((argResults!['lang'] as List).isEmpty) {
      lang = MultipleChoiceQuestion(
        question: 'Language',
        options: ['Java', 'Kotlin'],
      ).ask();
    } else {
      lang = argResults!['lang'].toString().trim();
    }

    final camelCasedName = Casing.camelCase(name);
    final pascalCasedName = Casing.pascalCase(name);

    // If the last word after '.' in package name is same as the
    // extension name, then
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

      CmdUtils.writeFile(
          p.join(projectDir, 'rush.yml'),
          getRushYamlTemp(
              pascalCasedName, versionName, authorName, lang == 'Kotlin'));

      CmdUtils.writeFile(
          p.join(projectDir, 'README.md'), getReadme(pascalCasedName));
      CmdUtils.writeFile(p.join(projectDir, '.gitignore'), getDotGitignore());
      CmdUtils.writeFile(p.join(projectDir, 'deps', '.placeholder'),
          'This directory stores your extension\'s dependencies.');

      // IntelliJ IDEA files
      CmdUtils.writeFile(p.join(projectDir, '.idea', 'misc.xml'), getMiscXml());
      CmdUtils.writeFile(
          p.join(projectDir, '.idea', 'libraries', 'dev-deps.xml'),
          getDevDepsXml(_dataDir));
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
    File(p.join(_dataDir, 'tools', 'other', 'icon-rush.png'))
        .copySync(p.join(projectDir, 'assets', 'icon.png'));

    Hive.init(p.join(projectDir, '.rush'));
    final box = await Hive.openBox('data');
    await box.putAll({
      'name': pascalCasedName,
      'version': 1,
      'org': orgName,
      'rushYmlLastMod': DateTime.now(),
      'srcDirLastMod': DateTime.now(),
    });

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
}
