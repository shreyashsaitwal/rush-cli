import 'dart:io' show Directory, File, Platform, exit;

import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:process_run/shell.dart';
import 'package:process_runner/process_runner.dart';
import 'package:rush_cli/java/helper.dart';
import 'package:rush_prompt/rush_prompt.dart';

enum CompileType { buildJ, buildKt, kapt, migrate }

class Compiler {
  final String _cd;
  final String _dataDir;

  Compiler(this._cd, this._dataDir);

  Future<void> compile(CompileType type, BuildStep step,
      {Box? dataBox, Directory? output}) async {
    final args;

    switch (type) {
      case CompileType.buildJ:
        if (dataBox == null) {
          throw Exception('dataBox: Expected type Box but found null');
        }
        args = await _getJavacArgs(dataBox);
        break;

      case CompileType.buildKt:
        if (dataBox == null) {
          throw Exception('dataBox: Expected type Box but found null');
        }
        args = _getKtcArgs(await dataBox.get('org'));
        break;

      case CompileType.kapt:
        if (dataBox == null) {
          throw Exception('dataBox: Expected type Box but found null');
        }
        args = await _getKaptArgs(
          await dataBox.get('name'),
          await dataBox.get('org'),
          await dataBox.get('version'),
        );
        break;

      case CompileType.migrate:
        if (output == null) {
          throw Exception(
              'output: Expected type dart.io.Directory but found null');
        }
        args = _getMigratorArgs(output);
        break;
    }

    var errCount = 0;
    var warnCount = 0;

    final stream = ProcessRunner(defaultWorkingDirectory: Directory(_cd))
        .runProcess(args)
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
        final errors = e.result?.stderr.split('\n');
        final pattern = RegExp(r'\d+\s(error(s)?|warning(s)?)');

        errors?.forEach((element) {
          if (element.contains('error: ')) {
            step.logErr(
                'src' + element.split('src').last.toString().trimRight(),
                addSpace: true);
            errCount++;
          } else if (!pattern.hasMatch(element.trim())) {
            step.logErr(' ' * 3 + element.toString().trimRight(),
                addPrefix: false);
            errCount++;
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

  Future<List<String>> _getJavacArgs(Box box) async {
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
      ..add('javac')
      ..addAll(['-d', classesDir.path])
      ..addAll(['-cp', classpath])
      ..addAll([...javacArgs])
      ..addAll([...srcFiles]);

    return args;
  }

  List<String> _getMigratorArgs(Directory output) {
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
      ..add('javac')
      ..addAll(['-d', classesDir.path])
      ..addAll(['-cp', classpath])
      ..addAll([...javacArgs])
      ..addAll([...srcFiles]);

    return args;
  }

  List<String> _getKtcArgs(String org) {
    final kotlinc = p.join(_dataDir, 'tools', 'kotlinc', 'bin',
        'kotlinc' + (Platform.isWindows ? '.bat' : ''));

    final devDeps = Directory(p.join(_cd, '.rush', 'dev-deps'));
    final deps = Directory(p.join(_cd, 'deps'));
    final classpath = Helper.generateClasspath([devDeps, deps]);

    final classesDir = Directory(p.join(_dataDir, 'workspaces', org, 'classes'))
      ..createSync(recursive: true);
    final srcDir = p.join(_cd, 'src');

    final args = <String>[];
    args
      ..addAll(['-d', classesDir.path])
      ..addAll(['-cp', '"$classpath"'])
      ..add(srcDir);

    final argFile = _writeArgFile('compile.rsh', org, args);

    return [kotlinc, '@${argFile.path}'];
  }

  Future<List<String>> _getKaptArgs(
      String name, String org, int version) async {
    final kotlincDir = p.join(_dataDir, 'tools', 'kotlinc');

    final devDeps = Directory(p.join(_cd, '.rush', 'dev-deps'));
    final deps = Directory(p.join(_cd, 'deps'));
    final apDir = Directory(p.join(_dataDir, 'tools', 'processor'));

    final classpath = Helper.generateClasspath([devDeps, deps, apDir],
        exclude: ['processor-v186a.jar']);

    final srcDir = p.join(_cd, 'src');

    final whichJavac = whichSync('javac') ?? whichSync('jar');
    final toolsJar =
        p.join(p.dirname(p.dirname(whichJavac!)), 'lib', 'tools.jar');

    final prefix = 'plugin:org.jetbrains.kotlin.kapt3:';
    final kaptDir = Directory(p.join(_dataDir, 'workspaces', org, 'kapt'))
      ..createSync(recursive: true);

    final apOpts = await _getEncodedApOpts(org, name, version);

    final args = <String>[];
    args
      ..addAll(['-cp', '"$classpath"'])
      ..add('-Xplugin="$toolsJar"')
      ..add(
          '-Xplugin="${p.join(kotlincDir, 'lib', 'kotlin-annotation-processing.jar')}"')
      ..add('-P "' + prefix + 'sources=' + kaptDir.path + '"')
      ..add('-P "' + prefix + 'classes=' + kaptDir.path + '"')
      ..add('-P "' + prefix + 'stubs=' + kaptDir.path + '"')
      ..add('-P "' + prefix + 'aptMode=stubsAndApt' + '"')
      ..add('-P "' +
          prefix +
          'apclasspath=' +
          p.join(apDir.path, 'processor-v186a.jar') +
          '"')
      ..add('-P "' + prefix + 'apoptions=' + apOpts + '"')
      ..add(srcDir);

    final argFile = _writeArgFile('kapt.rsh', org, args);

    return [
      p.join(kotlincDir, 'bin', 'kotlinc' + (Platform.isWindows ? '.bat' : '')),
      '@${argFile.path}'
    ];
  }

  Future<String> _getEncodedApOpts(String org, String name, int version) async {
    final opts = [
      'root=${_cd.replaceAll('\\', '/')}',
      'extName=$name',
      'org=$org',
      'version=$version',
      'output=${p.join(_dataDir, 'workspaces', org, 'classes')}'
    ].join(';');

    final encoder = p.join(_dataDir, 'tools', 'other', 'encoder-1.0.jar');

    final res =
        await ProcessRunner().runProcess(['java', '-jar', encoder, opts]);

    if (res.stderr.isEmpty) {
      return res.stdout.trim();
    } else {
      Logger.logErr('Something went wrong...', addSpace: true);
      Logger.logErr(res.stderr, addPrefix: false);
      exit(1);
    }
  }

  File _writeArgFile(String fileName, String org, List<String> args) {
    final file = File(p.join(_dataDir, 'workspaces', org, fileName))
      ..createSync(recursive: true);

    var contents = '';

    args.forEach((line) {
      contents += line.replaceAll('\\', '/') + '\n';
    });

    file.writeAsStringSync(contents);

    return file;
  }
}
