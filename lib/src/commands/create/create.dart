import 'package:args/command_runner.dart';
import 'package:collection/collection.dart';
import 'package:get_it/get_it.dart';
import 'package:interact/interact.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/src/commands/create/templates/eclipse_files.dart';
import 'package:tint/tint.dart';

import 'package:rush_cli/src/services/libs_service.dart';
import 'package:rush_cli/src/services/logger.dart';
import 'package:rush_cli/src/commands/create/casing.dart';
import 'package:rush_cli/src/utils/file_extension.dart';
import 'package:rush_cli/src/services/file_service.dart';
import 'package:rush_cli/src/commands/create/templates/extension_source.dart';
import 'package:rush_cli/src/commands/create/templates/intellij_files.dart';
import 'package:rush_cli/src/commands/create/templates/other.dart';

class CreateCommand extends Command<int> {
  final FileService _fs = GetIt.I<FileService>();

  CreateCommand() {
    argParser
      ..addOption('package',
          abbr: 'p',
          help:
              'The organization name in reverse domain name notation. This is used as extension\'s package name.')
      ..addOption('language',
          abbr: 'l',
          help:
              'The language in which the extension\'s starter template should be generated',
          allowed: ['Java', 'Kotlin']);
  }

  @override
  String get description =>
      'Scaffolds a new extension project in the current working directory.';

  @override
  String get name => 'create';

  /// Creates a new extension project in the current directory.
  @override
  Future<int> run() async {
    late String name;
    if (argResults!.rest.length == 1) {
      name = argResults!.rest.first;
    } else {
      printUsage();
      return 64; // Exit code 64 indicates usage error
    }

    final kebabCasedName = Casing.kebabCase(name);
    final projectDir = p.join(_fs.cwd, kebabCasedName);

    final dir = projectDir.asDir();
    if (await dir.exists() && dir.listSync().isNotEmpty) {
      throw Exception(
          'Cannot create "$projectDir" because it already exists and is not empty.');
    }

    var orgName = (argResults!['package'] ??
        Input(
          prompt: 'Package name',
        ).interact()) as String;

    var lang = argResults!['language'] as String?;
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

    final editor = Select(
      prompt: 'IDE',
      options: [
        'IntelliJ ${'(includes Android Studio and other JetBrains IDEs)'.grey()}',
        'Eclipse  ${'(includes Visual Studio Code)'.grey()}',
        'Both     ${'(includes every IDE mentioned above)'.grey()}',
      ],
    ).interact();

    final processing = Spinner(
        icon: '\n✅ '.green(),
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

    await GetIt.I.isReady<LibService>();
    final libService = GetIt.I<LibService>();

    final artifacts = await libService.providedDepArtifacts();
    final providedDepJars = artifacts.map((el) => el.classesJar).whereNotNull();
    final providedDepSources =
        artifacts.map((el) => el.sourcesJar).whereNotNull();

    final filesToCreate = <String, String>{
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
      p.join(projectDir, 'src', 'AndroidManifest.xml'):
          androidManifestXml(orgName),
      p.join(projectDir, 'src', 'proguard-rules.pro'): pgRules(orgName),
      p.join(projectDir, 'rush.yml'): config(lang == 'Kotlin'),
      p.join(projectDir, 'README.md'): readmeMd(pascalCasedName),
      p.join(projectDir, '.gitignore'): dotGitignore,
      p.join(projectDir, 'deps', '.placeholder'):
          'This directory stores your extension\'s local dependencies.',

      // IntelliJ IDEA files
      if (editor == 0 || editor == 2) ...{
        p.join(ideaDir, 'misc.xml'): ijMiscXml,
        p.join(ideaDir, 'libraries', 'local-deps.xml'): ijLocalDepsXml,
        p.join(ideaDir, 'libraries', 'provided-deps.xml'):
            ijProvidedDepsXml(providedDepJars, providedDepSources),
        p.join(ideaDir, '$kebabCasedName.iml'):
            ijImlXml(['provided-deps', 'local-deps']),
        p.join(ideaDir, 'modules.xml'): ijModulesXml(kebabCasedName),
      },
      // Eclipse files
      if (editor == 1 || editor == 2) ...{
        p.join(projectDir, '.project'): dotProject(kebabCasedName),
        p.join(projectDir, '.classpath'): dotClasspath(providedDepJars, []),
      },
    };

    // Creates the required files for the extension.
    try {
      filesToCreate.forEach((path, contents) async {
        path.asFile(true).writeAsStringSync(contents);
      });
      p.join(projectDir, 'assets').asDir(true);
      // Copy icon
      p
          .join(_fs.rushHomeDir.path, 'icon.png')
          .asFile()
          .copySync(p.join(projectDir, 'assets', 'icon.png'));
    } catch (e) {
      GetIt.I<Logger>().err(e.toString());
      rethrow;
    }

    processing.done();
    return 0;
  }
}
