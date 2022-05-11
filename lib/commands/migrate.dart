import 'dart:io' show File, Directory, exit;

import 'package:dart_console/dart_console.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/commands/rush_command.dart';
import 'package:rush_cli/utils/casing.dart';
import 'package:rush_cli/utils/cmd_utils.dart';
import 'package:rush_cli/utils/dir_utils.dart';
import 'package:rush_cli/utils/process_streamer.dart';
import 'package:rush_cli/services/file_service.dart';
import 'package:rush_cli/templates/dot_gitignore.dart';
import 'package:rush_cli/templates/intellij_files.dart';
import 'package:rush_cli/templates/readme.dart';
import 'package:rush_cli/templates/rules_pro.dart';
import 'package:rush_prompt/rush_prompt.dart';

class MigrateCommand extends RushCommand {
  final FileService _fs;

  MigrateCommand(this._fs);

  @override
  String get description =>
      'Migrates the extension-template project in the current directory to Rush.';

  @override
  String get name => 'migrate';

  @override
  Future<void> run() async {
    final dir = Directory(p.join(_fs.dataDir, 'workspaces'))..createSync();
    final outputDir = Directory(dir.path).createTempSync();

    final compStep = BuildStep('Introspecting the sources')..init();

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
        compStep.log(LogType.erro, ' ' * 5 + '- ' + el, addPrefix: false);
      }

      compStep
        ..log(LogType.erro,
            'Currently, Rush doesn\'t support multiple extensions inside one project.')
        ..finishNotOk();

      exit(1);
    }

    final extName = p
        .basenameWithoutExtension(genFiles['rushYml']!.first.path)
        .split('rush-')
        .last;
    final org = CmdUtils.getPackage(_fs.srcDir, extName: extName);

    final projectDir = Directory(
        p.join(p.dirname(_fs.cwd), Casing.kebabCase(extName) + '-rush'))
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

  /// Copies all the src files without performing any checks; it just copies
  /// everything except the assets and aiwebres directory.
  void _copySrcFiles(String package, String projectDirPath, BuildStep step) {
    final baseDir = Directory(p.joinAll([_fs.srcDir, ...package.split('.')]));

    final dest =
        Directory(p.joinAll([projectDirPath, 'src', ...package.split('.')]))
          ..createSync(recursive: true);

    DirUtils.copyDir(baseDir, dest, ignorePaths: [
      p.join(baseDir.path, 'assets'),
      p.join(baseDir.path, 'aiwebres'),
    ]);

    step.log(LogType.info, 'Copied source files');
  }

  /// Copies extension assets and icon.
  void _copyAssets(String package, String projectDirPath, BuildStep step) {
    final baseDir =
        Directory(p.joinAll([_fs.srcDir, ...package.split('.'), 'assets']));

    final assetsDir = Directory(p.join(baseDir.path, 'assets'));
    final assetsDest = Directory(p.join(projectDirPath, 'assets'))
      ..createSync();

    if (assetsDir.existsSync() && assetsDir.listSync().isNotEmpty) {
      DirUtils.copyDir(assetsDir, assetsDest);
    }

    final aiwebres = Directory(p.join(baseDir.path, 'aiwebres'));
    if (aiwebres.existsSync() && aiwebres.listSync().isNotEmpty) {
      DirUtils.copyDir(aiwebres, assetsDest);
    } else {
      File(p.join(_fs.toolsDir, 'other', 'icon-rush.png'))
          .copySync(p.join(projectDirPath, 'assets', 'icon.png'));
    }

    step.log(LogType.info, 'Copied assets');
  }

  /// Copies all necessary deps.
  void _copyDeps(String projectDir, BuildStep step) {
    final deps = Directory(p.join(_fs.cwd, 'lib', 'deps'));
    final depsDest = Directory(p.join(projectDir, 'deps'))..createSync();

    if (deps.existsSync() && deps.listSync().isNotEmpty) {
      DirUtils.copyDir(deps, depsDest);
    } else {
      CmdUtils.writeFile(p.join(depsDest.path, '.placeholder'),
          'This directory stores your extension\'s dependencies.');
    }

    step.log(LogType.info, 'Copied dependencies');
  }

  /// Generates files like readme, proguard-rules.pro, etc.
  void _genNecessaryFiles(String org, String extName, String projectDirPath) {
    final kebabCasedName = Casing.kebabCase(extName);

    CmdUtils.writeFile(p.join(projectDirPath, 'src', 'proguard-rules.pro'),
        getPgRules(org, extName));
    CmdUtils.writeFile(p.join(projectDirPath, 'README.md'), getReadme(extName));
    CmdUtils.writeFile(p.join(projectDirPath, '.gitignore'), getDotGitignore());

    // IntelliJ IDEA files
    final ideaDir = p.join(projectDirPath, '.idea');
    CmdUtils.writeFile(p.join(ideaDir, 'misc.xml'), getMiscXml());
    CmdUtils.writeFile(p.join(ideaDir, 'libraries', 'dev-deps.xml'),
        getDevDepsXml(_fs.dataDir));
    CmdUtils.writeFile(p.join(ideaDir, 'libraries', 'deps.xml'), getDepsXml());
    CmdUtils.writeFile(
        p.join(ideaDir, 'modules.xml'), getModulesXml(kebabCasedName));
    CmdUtils.writeFile(p.join(ideaDir, '$kebabCasedName.iml'),
        getIml(ideaDir, ['dev-deps', 'deps']));
  }

  Future<void> _compileJava(Directory output, BuildStep step) async {
    final args = () {
      final classpath = CmdUtils.classpathString([
        Directory(p.join(_fs.cwd, 'lib', 'appinventor')),
        Directory(p.join(_fs.cwd, 'lib', 'deps')),
        Directory(p.join(_fs.toolsDir, 'processor')),
        File(p.join(_fs.toolsDir, 'other', 'migrator.jar')),
        File(p.join(_fs.devDepsDir, 'kotlin', 'kotlin-stdlib.jar'))
      ], exclude: [
        'AnnotationProcessors.jar'
      ]);

      final javacArgs = <String>[
        '-Xlint:-options',
        '-AoutputDir=${output.path}',
      ];

      final srcFiles = CmdUtils.getJavaSourceFiles(Directory(_fs.srcDir));
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

    final result = await ProcessStreamer.stream(args, _fs.cwd);
    if (!result.success) {
      throw Exception();
    }
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
      ..write('Generated: ')
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
      ..write('  - remove all the unsupported annotations from ')
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
