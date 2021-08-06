import 'dart:io' show File, Directory, exit;

import 'package:args/command_runner.dart';
import 'package:dart_console/dart_console.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/helpers/casing.dart';
import 'package:rush_cli/helpers/cmd_utils.dart';
import 'package:rush_cli/helpers/dir_utils.dart';
import 'package:rush_cli/helpers/process_streamer.dart';
import 'package:rush_cli/templates/dot_gitignore.dart';
import 'package:rush_cli/templates/intellij_files.dart';
import 'package:rush_cli/templates/readme.dart';
import 'package:rush_cli/templates/rules_pro.dart';
import 'package:rush_prompt/rush_prompt.dart';

class MigrateCommand extends Command {
  final String _cd;
  final String _dataDir;

  MigrateCommand(this._cd, this._dataDir);

  @override
  String get description =>
      'Introspects and migrates the extension-template project in the current directory to Rush.';

  @override
  String get name => 'migrate';

  @override
  void printUsage() {
    PrintArt();

    Console()
      ..setForegroundColor(ConsoleColor.cyan)
      ..write(' migrate: ')
      ..resetColorAttributes()
      ..writeLine(description)
      ..writeLine()
      ..writeLine(' Usage: ')
      ..setForegroundColor(ConsoleColor.brightBlue)
      ..write('   rush ')
      ..setForegroundColor(ConsoleColor.cyan)
      ..write('migrate ')
      ..resetColorAttributes();
  }

  @override
  Future<void> run() async {
    final dir = Directory(p.join(_dataDir, 'cache'))..createSync();
    final outputDir = Directory(dir.path).createTempSync();

    final compStep = BuildStep('Introspecting the source files')..init();

    try {
      await _compileJava(outputDir, compStep);
    } catch (e) {
      compStep.finishNotOk();

      Logger.logCustom('Build failed',
          prefix: '\n• ', prefixFG: ConsoleColor.brightRed);
      exit(1);
    }

    final genFiles = {
      'rushYml': <File>[],
      'manifest': <File>[],
    };

    outputDir.listSync().whereType<File>().forEach((el) {
      final fileName = p.basenameWithoutExtension(el.path);
      if (fileName.startsWith('rush-')) {
        genFiles['rushYml']?.add(el);
      } else if (fileName.startsWith('manifest-')) {
        genFiles['manifest']?.add(el);
      }
    });

    if (genFiles.entries.any((el) => el.value.isEmpty)) {
      compStep
        ..log(LogType.erro, 'No extension found')
        ..finishNotOk();

      exit(1);
    } else if (genFiles.entries.any((el) => el.value.length > 1)) {
      final extensionNames = genFiles['rushYml']?.map(
              (e) => p.basenameWithoutExtension(e.path).split('rush-').last) ??
          [];

      compStep.log(LogType.erro, 'More than two extensions found');
      for (final el in extensionNames) {
        compStep.log(LogType.erro, ' ' * 2 + '- ' + el, addPrefix: false);
      }

      compStep
        ..log(LogType.erro,
            'Currently, Rush doesn\'t supports multiple extensions inside one project.')
        ..finishNotOk();

      exit(1);
    }

    final extName = p
        .basenameWithoutExtension(genFiles['rushYml']!.first.path)
        .split('rush-')
        .last;
    final org = CmdUtils.getPackage(extName, p.join(_cd, 'src'));

    final projectDir =
        Directory(p.join(p.dirname(_cd), Casing.kebabCase(extName) + '-rush'))
          ..createSync(recursive: true);

    final rushYmlDest = p.join(projectDir.path, 'rush.yml');
    genFiles['rushYml']!.first.copySync(rushYmlDest);

    final srcDir = Directory(p.join(projectDir.path, 'src'))..createSync();
    genFiles['manifest']!
        .first
        .copySync(p.join(srcDir.path, 'AndroidManifest.xml'));

    outputDir.deleteSync(recursive: true);
    compStep.finishOk();

    final finalStep = BuildStep('Finalizing the migration')..init();

    _copySrcFiles(org, projectDir.path, finalStep);
    _copyAssets(org, projectDir.path, finalStep);
    _copyDeps(projectDir.path, finalStep);
    _genNecessaryFiles(org, extName, projectDir.path);

    finalStep.finishOk();

    _printFooter(projectDir.path, Casing.kebabCase(extName), extName);
  }

  /// Copies all the src files.
  /// This doesn't perform any checks, just copies everything except the assets and
  /// aiwebres directory.
  void _copySrcFiles(String package, String projectDirPath, BuildStep step) {
    final baseDir = Directory(p.joinAll([_cd, 'src', ...package.split('.')]));

    final dest =
        Directory(p.joinAll([projectDirPath, 'src', ...package.split('.')]))
          ..createSync(recursive: true);

    CmdUtils.copyDir(baseDir, dest, ignore: [
      Directory(p.join(baseDir.path, 'assets')),
      Directory(p.join(baseDir.path, 'aiwebres')),
    ]);

    step.log(LogType.info, 'Copied source files');
  }

  /// Copies extension assets and icon.
  void _copyAssets(String package, String projectDirPath, BuildStep step) {
    final baseDir =
        Directory(p.joinAll([_cd, 'src', ...package.split('.'), 'assets']));

    final assetsDir = Directory(p.join(baseDir.path, 'assets'));
    final assetsDest = Directory(p.join(projectDirPath, 'assets'))
      ..createSync();

    if (assetsDir.existsSync() && assetsDir.listSync().isNotEmpty) {
      CmdUtils.copyDir(assetsDir, assetsDest);
    }

    final aiwebres = Directory(p.join(baseDir.path, 'aiwebres'));
    if (aiwebres.existsSync() && aiwebres.listSync().isNotEmpty) {
      CmdUtils.copyDir(aiwebres, assetsDest);
    } else {
      File(p.join(_dataDir, 'tools', 'other', 'icon-rush.png'))
          .copySync(p.join(projectDirPath, 'assets', 'icon.png'));
    }

    step.log(LogType.info, 'Copied assets');
  }

  /// Copies all necessary deps.
  void _copyDeps(String projectDir, BuildStep step) {
    final deps = Directory(p.join(_cd, 'lib', 'deps'));
    final depsDest = Directory(p.join(projectDir, 'deps'))..createSync();

    if (deps.existsSync() && deps.listSync().isNotEmpty) {
      CmdUtils.copyDir(deps, depsDest);
    } else {
      _writeFile(p.join(depsDest.path, '.placeholder'),
          'This directory stores your extension\'s depenedencies.');
    }

    step.log(LogType.info, 'Copied dependencies');
  }

  /// Generates files like readme, proguard-rules.pro, etc.
  void _genNecessaryFiles(String org, String extName, String projectDirPath) {
    final kebabCasedName = Casing.kebabCase(extName);

    _writeFile(p.join(projectDirPath, 'src', 'proguard-rules.pro'),
        getPgRules(org, extName));
    _writeFile(p.join(projectDirPath, 'README.md'), getReadme(extName));
    _writeFile(p.join(projectDirPath, '.gitignore'), getDotGitignore());

    // IntelliJ IDEA files
    _writeFile(p.join(projectDirPath, '.idea', 'misc.xml'), getMiscXml());
    _writeFile(p.join(projectDirPath, '.idea', 'libraries', 'dev-deps.xml'),
        getDevDepsXml(_dataDir));
    _writeFile(
        p.join(projectDirPath, '.idea', 'libraries', 'deps.xml'), getDepsXml());
    _writeFile(p.join(projectDirPath, '.idea', 'modules.xml'),
        getModulesXml(kebabCasedName));
    _writeFile(p.join(projectDirPath, '.idea', '$kebabCasedName.iml'), getIml());
  }

  Future<void> _compileJava(Directory output, BuildStep step) async {
    final args = () {
      final devDeps = Directory(p.join(_cd, 'lib', 'appinventor'));
      final deps = Directory(p.join(_cd, 'lib', 'deps'));
      final migrator = File(p.join(_dataDir, 'tools', 'other', 'migrator.jar'));

      final classpath = CmdUtils.generateClasspath([devDeps, deps, migrator],
          exclude: ['AnnotationProcessors.jar']);

      final javacArgs = <String>[
        '-Xlint:-options',
        '-AoutputDir=${output.path}',
      ];

      final srcFiles =
          CmdUtils.getJavaSourceFiles(Directory(p.join(_cd, 'src')));
      final classesDir = Directory(p.join(output.path, 'classes'))
        ..createSync();

      final args = <String>[];
      args
        ..add('javac')
        ..addAll(['-d', classesDir.path])
        ..addAll(['-cp', classpath])
        ..addAll([...javacArgs])
        ..addAll([...srcFiles]);

      return args;
    }();

    final result = await ProcessStreamer.stream(args, _cd);
    if (result.result == Result.error) {
      throw Exception();
    }
  }

  /// Creates a file in [path] and writes [content] inside it.
  void _writeFile(String path, String content) {
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  /// Prints the footer.
  void _printFooter(String projectDir, String kebabCasedName, String extName) {
    Console()
      ..writeLine()
      ..setForegroundColor(ConsoleColor.green)
      ..write('• ')
      ..setForegroundColor(ConsoleColor.brightGreen)
      ..write('Success! ')
      ..resetColorAttributes()
      ..writeLine(
          'Migrated the extension-template project in the current directory to Rush.')
      ..write('  The generated Rush extension project can be found here: ')
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
      ..write('../' + kebabCasedName + '-rush')
      ..resetColorAttributes()
      ..writeLine(',')
      ..write(
          '  - remove all the unsupported annotations (like, @DesignerComponent, @UsesPermissions, etc) and their imports from ')
      ..setForegroundColor(ConsoleColor.brightBlue)
      ..write(extName + '.java')
      ..resetColorAttributes()
      ..writeLine(', and then')
      ..write(' ' * 2 + '- run ')
      ..setForegroundColor(ConsoleColor.brightBlue)
      ..write('rush build ')
      ..resetColorAttributes()
      ..writeLine('to compile your extension.');
  }
}
