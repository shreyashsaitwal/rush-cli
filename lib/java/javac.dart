import 'dart:io' show Directory, File;

import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:process_runner/process_runner.dart';
import 'package:rush_cli/java/helper.dart';
import 'package:rush_prompt/rush_prompt.dart';

enum CompileType { build, migrate }

class Javac {
  final String _cd;
  final String _dataDir;

  Javac(this._cd, this._dataDir);

  Future<void> compile(CompileType type, BuildStep step,
      {Box? dataBox, Directory? output}) async {
    final args;

    if (type == CompileType.build) {
      if (dataBox == null) {
        throw Exception('dataBox: Expected type Box but found null');
      }
      args = await _generateBuildArgs(dataBox);
    } else {
      if (output == null) {
        throw Exception(
            'output: Expected type dart.io.Directory but found null');
      }
      args = _generateMigratorArgs(output);
    }

    var errCount = 0;
    var warnCount = 0;

    final stream = ProcessRunner(defaultWorkingDirectory: Directory(_cd))
        .runProcess(['javac', ...args])
        .asStream()
        .asBroadcastStream();

    try {
      await for (final result in stream) {
        final output = result.output.split('\n');

        var previous = '';
        output
            .where((element) =>
                element.contains('warning: ') &&
                !element.contains(
                    'The following options were not recognized by any processor:'))
            .forEach((element) {
          final formatted = element.replaceFirst('warning: ', '').trimRight();

          if (formatted != previous) {
            step.logWarn(formatted, addSpace: true);
            warnCount++;
          }

          previous = formatted;
        });
      }
    } catch (e) {
      if (e is ProcessRunnerException) {
        final errors = e.result!.stderr.split('\n');
        final pattern = RegExp(r'\d+\s(error(s)?|warning(s)?)');

        errors.forEach((element) {
          if (element.contains('error: ')) {
            step.logErr(
                'src' + element.split('src').last.toString().trimRight(),
                addSpace: true);
            errCount++;
          } else if (!pattern.hasMatch(element.trim())) {
            step.logErr(' ' * 3 + element.toString().trimRight(),
                addPrefix: false);
          }
        });
      } else {
        errCount++;
        step.logErr(e.toString().trimRight(), addSpace: true);
      }
    }

    if (warnCount > 0) {
      step.logWarn('Total warning(s): ' + warnCount.toString().trimRight(),
          addSpace: true, addPrefix: false);
    }
    if (errCount > 0) {
      step.logErr('Total error(s): ' + errCount.toString().trimRight(),
          addPrefix: false);

      throw Exception('Failed');
    }
  }

  Future<List<String>> _generateBuildArgs(Box box) async {
    final name = await box.get('name');
    final org = await box.get('org');
    final version = await box.get('version') as int;

    final srcDir = Directory(p.join(_cd, 'src'));
    final classesDir = Directory(p.join(_dataDir, 'workspaces', org, 'classes'))
      ..createSync(recursive: true);

    final devDeps = Directory(p.join(_cd, '.rush', 'dev-deps'));
    final deps = Directory(p.join(_cd, 'deps'));
    final processor = Directory(p.join(_dataDir, 'tools', 'processor'));

    final javacArgs = <String>[
      '-Xlint:-options',
      '-Aroot=$_cd',
      '-AextName=$name',
      '-Aorg=$org',
      '-Aversion=$version',
      '-Aoutput=${classesDir.path}',
    ];
    final classpath = Helper.generateClasspath([devDeps, deps, processor]);

    final srcFiles = Helper.getSourceFiles(srcDir);

    final args = <String>[];
    args
      ..addAll(['-d', classesDir.path])
      ..addAll(['-cp', classpath])
      ..addAll([...javacArgs])
      ..addAll([...srcFiles]);

    return args;
  }

  List<String> _generateMigratorArgs(Directory output) {
    final devDeps = Directory(p.join(_cd, 'lib', 'appinventor'));
    final deps = Directory(p.join(_cd, 'lib', 'deps'));
    final migrator = File(p.join(_dataDir, 'tools', 'other', 'migrator.jar'));

    final classpath = Helper.generateClasspath([devDeps, deps, migrator],
        exclude: ['AnnotationProcessors.jar']);
    final javacArgs = <String>[
      '-Xlint:-options',
      '-AoutputDir=${output.path}',
    ];

    final srcFiles = Helper.getSourceFiles(Directory(p.join(_cd, 'src')));

    final classesDir = Directory(p.join(output.path, 'classes'))..createSync();

    final args = <String>[];
    args
      ..addAll(['-d', classesDir.path])
      ..addAll(['-cp', classpath])
      ..addAll([...javacArgs])
      ..addAll([...srcFiles]);

    return args;
  }
}
