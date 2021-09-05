import 'dart:io' show Directory, File, exit;

import 'package:args/command_runner.dart';
import 'package:dart_console/dart_console.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/commands/build/hive_adapters/build_box.dart';
import 'package:rush_cli/services/file_service.dart';
import 'package:rush_prompt/rush_prompt.dart';

class CleanCommand extends Command<void> {
  final FileService _fs;

  CleanCommand(this._fs);

  @override
  String get description =>
      'Clears the build directory and other build indexes.';

  @override
  String get name => 'clean';

  @override
  void printUsage() {
    PrintArt();
    Console()
      ..setForegroundColor(ConsoleColor.cyan)
      ..write(' clean ')
      ..resetColorAttributes()
      ..writeLine(description)
      ..writeLine()
      ..write(' Usage: ')
      ..setForegroundColor(ConsoleColor.brightBlue)
      ..write('rush ')
      ..setForegroundColor(ConsoleColor.cyan)
      ..writeLine('clean ')
      ..resetColorAttributes();
  }

  @override
  Future<void> run() async {
    PrintArt();
    final step = BuildStep('Cleaning')..init();

    if (!isRushProject()) {
      step
        ..log(LogType.erro, 'Current directory is not a Rush project')
        ..finishNotOk();
      exit(1);
    }

    final buildDir = Directory(_fs.buildDir);
    if (buildDir.existsSync()) {
      try {
        buildDir.deleteSync(recursive: true);
      } catch (e) {
        step.log(LogType.erro, 'Unable to delete the build directory');
        for (final line in e.toString().split('\n')) {
          step.log(LogType.erro, line, addPrefix: false);
        }
        step.finishNotOk();
        exit(1);
      }
    }
    step.log(LogType.info, 'Cleaned the old build files');

    Hive
      ..init(p.join(_fs.cwd, '.rush'))
      ..registerAdapter(BuildBoxAdapter());
    final buildBox = await Hive.openBox('build');
    await buildBox.clear();

    final rushLock = File(p.join(_fs.cwd, '.rush', 'rush.lock'));
    if (rushLock.existsSync()) {
      try {
        rushLock.deleteSync();
      } catch (e) {
        step.log(LogType.erro, 'Unable to delete rush.lock');
        for (final line in e.toString().split('\n')) {
          step.log(LogType.erro, line, addPrefix: false);
        }
        step.finishNotOk();
        exit(1);
      }
    }

    step
      ..log(LogType.info, 'Cleaned other build indexes')
      ..finishOk();
  }

  bool isRushProject() {
    final rushYaml = () {
      final yml = File(p.join(_fs.cwd, 'rush.yml'));

      if (yml.existsSync()) {
        return yml;
      } else {
        return File(p.join(_fs.cwd, 'rush.yaml'));
      }
    }();

    final srcDir = Directory(_fs.srcDir);
    final androidManifest = File(p.join(srcDir.path, 'AndroidManifest.xml'));
    final dotRushDir = Directory(p.join(_fs.cwd, '.rush'));

    return rushYaml.existsSync() &&
        srcDir.existsSync() &&
        androidManifest.existsSync() &&
        dotRushDir.existsSync();
  }
}
