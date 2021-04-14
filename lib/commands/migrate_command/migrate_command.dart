import 'dart:io';

import 'package:dart_console/dart_console.dart';
import 'package:path/path.dart' as p;
import 'package:args/command_runner.dart';
import 'package:rush_cli/commands/build_command/helper.dart';
import 'package:rush_cli/commands/create_command/casing.dart';
import 'package:rush_cli/javac_errors/err_data.dart';
import 'package:rush_cli/mixins/app_data_dir_mixin.dart';
import 'package:rush_cli/mixins/copy_mixin.dart';
import 'package:rush_cli/templates/dot_gitignore.dart';
import 'package:rush_cli/templates/iml_template.dart';
import 'package:rush_cli/templates/libs_xml.dart';
import 'package:rush_cli/templates/misc_xml.dart';
import 'package:rush_cli/templates/modules_xml.dart';
import 'package:rush_cli/templates/readme_template.dart';
import 'package:rush_cli/templates/rules_pro.dart';
import 'package:rush_prompt/rush_prompt.dart';

class MigrateCommand extends Command with AppDataMixin, CopyMixin {
  final String cd;
  final String binDir;

  MigrateCommand(this.cd, this.binDir);

  @override
  String get description =>
      'Introspects and migrates the extension-template project in CWD to Rush.';

  @override
  String get name => 'migrate';

  @override
  void printUsage() {
    PrintArt();

    Console()
      ..setForegroundColor(ConsoleColor.cyan)
      ..write(' migrate: ')
      ..setForegroundColor(ConsoleColor.brightWhite)
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
    final dir = Directory(p.join(AppDataMixin.dataStorageDir()!, 'cache'))
      ..createSync();
    final outputDir = Directory(dir.path).createTempSync();

    final compStep = BuildStep('Introspecting the Java files')..init();
    await _runMigrator(outputDir.path, compStep);

    final genFiles = {
      'rushYml': <File>[],
      'manifest': <File>[],
    };
    for (final file in outputDir.listSync()) {
      if (file is File) {
        final fileName = p.basenameWithoutExtension(file.path);
        if (fileName.startsWith('rush-')) {
          genFiles['rushYml']?.add(file);
        } else if (fileName.startsWith('manifest-')) {
          genFiles['manifest']?.add(file);
        }
      }
    }

    if (genFiles.entries.any((el) => el.value.isEmpty)) {
      compStep
        ..logErr('No extension found')
        ..finish('Failed', ConsoleColor.red);

      exit(1);
    } else if (genFiles.entries.any((el) => el.value.length > 1)) {
      final extensionNames = genFiles['rushYml']
          ?.map((e) => p.basenameWithoutExtension(e.path).split('rush-').last);

      compStep.logErr('More than two extensions found');
      extensionNames?.forEach((el) {
        compStep.logErr(' ' * 2 + '- ' + el, addPrefix: false);
      });
      compStep
        ..logErr(
            'Currently, Rush doesn\'t supports multiple extensions inside one project.',
            addPrefix: false,
            addSpace: true)
        ..finish('Failed', ConsoleColor.red);

      exit(1);
    }

    final extName = p
        .basenameWithoutExtension(genFiles['rushYml']!.first.path)
        .split('rush-')
        .last;
    final package = Helper.getPackage(extName, p.join(cd, 'src'));
    final projectDir =
        Directory(p.join(p.dirname(cd), Casing.kebabCase(extName)))
          ..createSync(recursive: true);

    final rushYmlDest = p.join(projectDir.path, 'rush.yml');
    genFiles['rushYml']!.first.copySync(rushYmlDest);

    final srcDir = Directory(p.join(projectDir.path, 'src'))..createSync();
    genFiles['manifest']!
        .first
        .copySync(p.join(srcDir.path, 'AndroidManifest.xml'));

    outputDir.deleteSync(recursive: true);
    compStep.finish('Done', ConsoleColor.green);

    final finalStep = BuildStep('Finalizing the migration')..init();

    _copySrcFiles(package, projectDir.path, finalStep);
    _copyAssets(package, projectDir.path, finalStep);
    _copyDeps(projectDir.path, finalStep);
    _genNecessaryFiles(extName);

    finalStep.finish('Done', ConsoleColor.green);

    _printFooter(projectDir.path, Casing.kebabCase(extName));
  }

  /// Copies all the src files.
  /// This doesn't perform any checks, just copies everything except the assets and
  /// aiwebres directory.
  void _copySrcFiles(String package, String projectDirPath, BuildStep step) {
    final baseDir = Directory(p.joinAll([cd, 'src', ...package.split('.')]));
    final dest =
        Directory(p.joinAll([projectDirPath, 'src', ...package.split('.')]))
          ..createSync(recursive: true);

    copyDir(baseDir, dest, ignore: [
      Directory(p.join(baseDir.path, 'assets')),
      Directory(p.join(baseDir.path, 'aiwebres')),
    ]);
    step.log('Copied source files', ConsoleColor.cyan,
        prefix: 'OK',
        prefBG: ConsoleColor.brightGreen,
        prefFG: ConsoleColor.black);
  }

  /// Copies extension assets and icon.
  void _copyAssets(String package, String projectDirPath, BuildStep step) {
    final baseDir =
        Directory(p.joinAll([cd, 'src', ...package.split('.'), 'assets']));

    final assetsDir = Directory(p.join(baseDir.path, 'assets'));
    final assetsDest = Directory(p.join(projectDirPath, 'assets'))
      ..createSync();

    if (assetsDir.existsSync() && assetsDir.listSync().isNotEmpty) {
      copyDir(assetsDir, assetsDest);
    }

    final aiwebres = Directory(p.join(baseDir.path, 'aiwebres'));
    if (aiwebres.existsSync() && aiwebres.listSync().isNotEmpty) {
      copyDir(aiwebres, assetsDest);
    }
    step.log('Copied assets', ConsoleColor.cyan,
        prefix: 'OK',
        prefBG: ConsoleColor.brightGreen,
        prefFG: ConsoleColor.black);
  }

  /// Copies all necessary deps.
  void _copyDeps(String projectDir, BuildStep step) {
    final devDeps = Directory(p.join(p.dirname(binDir), 'dev-deps'));
    final devDepsDest = Directory(p.join(projectDir, '.rush', 'dev-deps'))
      ..createSync(recursive: true);
    copyDir(devDeps, devDepsDest);

    final deps = Directory(p.join(cd, 'lib', 'deps'));
    final depsDest = Directory(p.join(projectDir, 'deps'))..createSync();
    if (deps.existsSync() && deps.listSync().isNotEmpty) {
      copyDir(deps, depsDest);
    } else {
      _writeFile(p.join(depsDest.path, '.placeholder'),
          'This directory stores your extension\'s depenedencies.');
    }
    step.log('Copied dependencies', ConsoleColor.cyan,
        prefix: 'OK',
        prefBG: ConsoleColor.brightGreen,
        prefFG: ConsoleColor.black);
  }

  /// Generates files like readme, proguard-rules.pro, etc.
  void _genNecessaryFiles(String extName) {
    final kebabCasedName = Casing.kebabCase(extName);
    final projectDir = p.join(p.dirname(cd), kebabCasedName);

    _writeFile(p.join(projectDir, 'src', 'proguard-rules.pro'), getPgRules());
    _writeFile(p.join(projectDir, 'README.md'), getReadme(extName));
    _writeFile(p.join(projectDir, '.gitignore'), getDotGitignore());

    // IntelliJ IDEA files
    _writeFile(p.join(projectDir, '.idea', 'misc.xml'), getMiscXml());
    _writeFile(
        p.join(projectDir, '.idea', 'libraries', 'dev-deps.xml'), getLibsXml());
    _writeFile(p.join(projectDir, '.idea', 'modules.xml'),
        getModulesXml(kebabCasedName));
    _writeFile(p.join(projectDir, '$kebabCasedName.iml'), getIml());
  }

  /// Creates a file in [path] and writes [content] inside it.
  void _writeFile(String path, String content) {
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  /// Runs the migrator which is simply an annotation processor that compiles the
  /// src files and generates the metadata file and AndroidManifest accordingly.
  Future<void> _runMigrator(String outputDir, BuildStep step) async {
    final antPath =
        p.join(p.dirname(binDir), 'tools', 'apache-ant-1.10.9', 'bin', 'ant');

    final args = [
      '-buildfile=${p.join(p.dirname(binDir), 'tools', 'apache-ant-1.10.9', 'build.xml')}',
      '-DantCon=${p.join(p.dirname(binDir), 'tools', 'ant-contrib', 'ant-contrib-1.0b3.jar')}',
      'migrate',
      '-Dclasses=${p.join(outputDir, 'classes')}',
      '-DextSrc=${p.join(cd, 'src')}',
      '-DoutputDir=$outputDir',
      '-DdevDeps=${p.join(cd, 'lib', 'appinventor')}',
      '-Ddeps=${p.join(cd, 'lib', 'deps')}',
      '-DtoolsDir=${p.join(p.dirname(binDir), 'tools')}',
    ];

    var count = 0;
    var errCount = 0;

    // Spawn the javac process
    final javacStream = Process.start(antPath, args, runInShell: true)
        .asStream()
        .asBroadcastStream();

    await for (final process in javacStream) {
      final stdoutStream = process.stdout.asBroadcastStream();

      await for (final data in stdoutStream) {
        final formatted = Helper.format(data);

        for (final out in formatted) {
          final lines = ErrData.getNoOfLines(out);

          if (lines != null) {
            count = lines - 1;
            final msg = 'src' + out.split('src').last;
            step.logErr(msg, addSpace: true);

            errCount++;
          } else if (count > 0) {
            count--;
            step.logErr(out, addPrefix: false);
          } else if (out.contains('ERR ')) {
            final msg = out.split('ERR ').last;
            step.logErr(msg, addSpace: true);

            errCount++;
          } else if (out.contains('error: ')) {
            count += 4;
            final msg = 'src' + out.split('src').last;
            step.logErr(msg, addSpace: true);

            errCount++;
          }
          /*else if (argResults!['extended-output'] &&
              !out.startsWith('Buildfile:')) {
            Logger.log(out.trimRight());
          }*/
        }
      }
    }

    if (errCount > 0) {
      step
        ..log('', ConsoleColor.white)
        ..log('Total error(s): ' + errCount.toString(), ConsoleColor.red,
            addSpace: false)
        ..finish('Failed', ConsoleColor.red);
      exit(1);
    }
  }

  /// Prints the footer.
  void _printFooter(String projectDir, String kebabCasedName) {
    Console()
      ..writeLine()
      ..setForegroundColor(ConsoleColor.green)
      ..write('• ')
      ..setForegroundColor(ConsoleColor.brightGreen)
      ..write('Success! ')
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..writeLine(
          'Migrated the extension-template project in the current directory to Rush.')
      ..write('  Generated Rush project can be found here: ')
      ..setForegroundColor(ConsoleColor.cyan)
      ..writeLine(projectDir)
      ..writeLine()
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..write('Next up, \n' + ' ' * 2 + '-')
      ..setForegroundColor(ConsoleColor.yellow)
      ..write(' cd ')
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..write('into ')
      ..setForegroundColor(ConsoleColor.brightBlue)
      ..write('../' + kebabCasedName + '/')
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..writeLine(', and')
      ..write(' ' * 2 + '- run ')
      ..setForegroundColor(ConsoleColor.brightBlue)
      ..write('rush build ')
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..writeLine('to compile your extension.')
      ..resetColorAttributes();
  }
}
