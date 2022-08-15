import 'dart:io' show Directory, File, exit;
import 'dart:math';

import 'package:get_it/get_it.dart';
import 'package:interact/interact.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/commands/rush_command.dart';
import 'package:rush_cli/utils/casing.dart';
import 'package:rush_cli/utils/utils.dart';
import 'package:rush_cli/services/file_service.dart';
import 'package:rush_cli/templates/android_manifest.dart';
import 'package:rush_cli/templates/dot_gitignore.dart';
import 'package:rush_cli/templates/extension_source.dart';
import 'package:rush_cli/templates/intellij_files.dart';
import 'package:rush_cli/templates/readme.dart';
import 'package:rush_cli/templates/rules_pro.dart';
import 'package:rush_cli/templates/rush_yml.dart';
import 'package:tint/tint.dart';

class CreateCommand extends RushCommand {
  final FileService _fs = GetIt.I<FileService>();

  CreateCommand() {
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

    final dir = Directory(projectDir);
    if (await dir.exists() && dir.listSync().isNotEmpty) {
      throw Exception(
          'Cannot create "$projectDir" because it already exists and is not empty.');
    }

    var orgName = (argResults!['org'] ??
        Input(
          prompt: 'Organisation (package name)',
        ).interact()) as String;

    var lang = argResults!['lang'] as String?;
    if (lang == null) {
      final opts = ['Java', 'Kotlin'];
      final index = Select(
        prompt: 'Language',
        options: opts,
      ).interact();
      lang = opts[index];
    }

    final camelCasedName = Casing.camelCase(name);
    final pascalCasedName = Casing.pascalCase(name);

    // If the last word after '.' in package name is not same as the extension
    // name, then append `.$extName` to orgName.
    final isOrgAndNameSame =
        orgName.split('.').last.toLowerCase() == camelCasedName.toLowerCase();
    if (!isOrgAndNameSame) {
      orgName = orgName.toLowerCase() + '.' + camelCasedName.toLowerCase();
    }

    // TODO: Colorize the spinner output
    final processing = Spinner(
        icon: '\n✔'.green(),
        rightPrompt: (done) => !done
            ? 'Getting things ready...'
            : '''
${'Success!'.green()} Generated a new extension project in ${p.relative(projectDir).blue()}.
  Next up,
    - ${'cd'.yellow()} into ${p.relative(projectDir).blue()}, and
    - run ${'rush build'.yellow()} to build your extension.
''').interact();

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
      p.join(ideaDir, 'libraries', 'dev-deps.xml'):
          getDevDepsXml(_fs.dataDir.path),
      p.join(ideaDir, 'libraries', 'deps.xml'): getDepsXml(),
      p.join(ideaDir, 'modules.xml'): getModulesXml(kebabCasedName),
      p.join(ideaDir, '$kebabCasedName.iml'):
          getIml(ideaDir, ['dev-deps', 'deps'])
    };

    // Creates the required files for the extension.
    try {
      filesToCreate.forEach((path, contents) async {
        await Utils.writeFile(path, contents);
      });

      await Directory(p.join(projectDir, 'assets')).create(recursive: true);
    } catch (e) {
      rethrow;
    }

    // Copy icon
    await File(p.join(_fs.toolsDir.path, 'other', 'icon-rush.png'))
        .copy(p.join(projectDir, 'assets', 'icon.png'));

    // All the above operations are blazingly fast. Wait a couple of seconds
    // to show that nice spinner. :P
    await Future.delayed(Duration(milliseconds: Random().nextInt(2000)));
    processing.done();
  }
}
