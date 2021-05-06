import 'dart:io' show Directory, File, Platform;

import 'package:process_runner/process_runner.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/helpers/copy.dart';
import 'package:rush_cli/java/helper.dart';
import 'package:rush_prompt/rush_prompt.dart';

enum CmdType { generator, d8, d8sup, proguard, jar, jetifier }

class CmdRunner {
  final String _cd;
  final String _dataDir;

  CmdRunner(this._cd, this._dataDir);

  var _shouldDejet = true;
  bool get getShouldDejet => _shouldDejet;

  /// Runs the specified [cmd], printing the required stdout and the whole
  /// stderr.
  ///
  /// If any error is caught, the [onError] function is invoked.
  ///
  /// If everything goes well, the [onSuccess] function is invoked.
  Future<void> run(CmdType cmd, String org, BuildStep step) async {
    final args = <String>[];
    var dwd = _cd; // Default working directory

    switch (cmd) {
      case CmdType.generator:
        args.addAll(_getGeneratorArgs(org));
        break;
      case CmdType.d8:
        args.addAll(_getD8Args(org, false));
        break;
      case CmdType.d8sup:
        args.addAll(_getD8Args(org, true));
        break;
      case CmdType.jar:
        dwd = p.join(_dataDir, 'workspaces', org, 'raw-classes', org);
        args.addAll(_getJarArgs(org, dwd));
        break;
      case CmdType.proguard:
        args.addAll(_getPgArgs(org));
        break;
      case CmdType.jetifier:
        args.addAll(_getJetifierArgs(org));
        break;
    }

    var failed = false;

    final stream = ProcessRunner(defaultWorkingDirectory: Directory(dwd))
        .runProcess(args)
        .asStream()
        .asBroadcastStream();

    try {
      await for (final result in stream) {
        if (cmd == CmdType.jetifier) {
          final pattern =
              RegExp(r'WARNING: \[Main\] No references were rewritten.');

          if (_shouldDejet) {
            _shouldDejet = !result.stdout.contains(pattern);
          }
        }
      }
    } catch (e) {
      if (e is ProcessRunnerException) {
        final errList = e.result!.stderr.split('\n');

        errList.forEach((err) {
          if (err.trim() != '') {
            if (err.startsWith(RegExp(r'\s'))) {
              if (cmd == CmdType.proguard) {
                step.logWarn(err, addPrefix: false);
              } else {
                step.logErr(err, addPrefix: false);
              }
            } else {
              final errPattern = RegExp(r'error:?\s?', caseSensitive: false);

              if (err.startsWith(errPattern)) {
                err = err.replaceAll(errPattern, '');
                step.logErr(err, addSpace: true);
              } else if (cmd == CmdType.proguard &&
                  err.startsWith('Warning: ')) {
                err = err.replaceAll('Warning: ', '');
                step.logWarn(err, addSpace: true);
              } else {
                step.logErr(err, addSpace: true);
              }
            }
          }
        });

        failed = true;
      } else {
        step.logErr(e.toString().trimRight(), addSpace: true);
      }
    }

    if (failed) {
      throw Exception('Failed');
    }
  }

  /// Returns the args required for running the extension generator.
  List<String> _getGeneratorArgs(String org) {
    final args = <String>['java'];

    final devDeps = Directory(p.join(_cd, '.rush', 'dev-deps'));
    final processor = Directory(p.join(_dataDir, 'tools', 'processor'));

    final classpath = Helper.generateClasspath([devDeps, processor]);

    final classesDir =
        Directory(p.join(_dataDir, 'workspaces', org, 'classes'));
    final rawClassesDir =
        Directory(p.join(_dataDir, 'workspaces', org, 'raw-classes'))
          ..createSync(recursive: true);
    final rawDirX = Directory(p.join(_dataDir, 'workspaces', org, 'raw', 'x'))
      ..createSync(recursive: true);

    final deps = p.join(_cd, 'deps');

    args
      ..addAll(['-cp', classpath])
      ..add('io.shreyash.rush.ExtensionGenerator')
      ..addAll([
        p.join(classesDir.path, 'simple_components.json'),
        p.join(classesDir.path, 'simple_components_build_info.json'),
        rawDirX.path,
        classesDir.path,
        deps,
        rawClassesDir.path,
        'false',
        _cd,
      ]);

    return args;
  }

  /// Returns the args required for running D8.
  List<String> _getD8Args(String org, bool isSup) {
    final args = <String>['java'];

    final d8 = File(p.join(_dataDir, 'tools', 'other', 'd8.jar'));
    final rawOrgDirX =
        Directory(p.join(_dataDir, 'workspaces', org, 'raw', 'x', org));
    final rawOrgDirSup =
        Directory(p.join(_dataDir, 'workspaces', org, 'raw', 'sup', org));

    final rawPath = isSup ? rawOrgDirSup.path : rawOrgDirX.path;
    args
      ..addAll(['-cp', d8.path])
      ..add('com.android.tools.r8.D8')
      ..addAll([
        '--release',
        '--no-desugaring',
        '--output',
        p.join(rawPath, 'classes.jar'),
        p.join(rawPath, 'files', 'AndroidRuntime.jar'),
      ]);

    return args;
  }

  /// Returns the args required for running the jar tool, which is used create a JAR.
  List<String> _getJarArgs(String org, String dwd) {
    final jar;
    if (Platform.isWindows) {
      jar = 'jar.exe';
    } else {
      jar = 'jar';
    }

    final args = <String>[jar, 'cf', '../$org.jar'];

    final rawClassesOrgDir = Directory(dwd);

    // Add everything that needs to be jarred
    rawClassesOrgDir.listSync().forEach((entity) {
      if (entity is Directory) {
        args.add(p.relative(entity.path, from: dwd));
      } else if (p.extension(entity.path) == '.class') {
        args.add(p.relative(entity.path));
      }
    });

    return args;
  }

  /// Returns the args required for running ProGuard
  List<String> _getPgArgs(String org) {
    final proguardJar =
        File(p.join(_dataDir, 'tools', 'other', 'proguard.jar'));

    final devDeps = Directory(p.join(_cd, '.rush', 'dev-deps'));
    final deps = Directory(p.join(_cd, 'deps'));

    final libraryJars = Helper.generateClasspath([devDeps, deps]);

    final rawClasses =
        Directory(p.join(_dataDir, 'workspaces', org, 'raw-classes'));
    final injar = File(p.join(rawClasses.path, '$org.jar'));
    final outjar = File(p.join(rawClasses.path, '${org}_pg.jar'));

    final pgRules = File(p.join(_cd, 'src', 'proguard-rules.pro'));

    final args = <String>['java', '-jar', proguardJar.path];
    args
      ..addAll(['-injars', injar.path])
      ..addAll(['-outjars', outjar.path])
      ..addAll(['-libraryjars', libraryJars])
      ..add('@${pgRules.path}');

    return args;
  }

  /// Returns the args required for running jetifier-standalone.
  List<String> _getJetifierArgs(String org) {
    final rawOrgDir =
        Directory(p.join(_dataDir, 'workspaces', org, 'raw', 'x', org));
    final rawOrgDirSup =
        Directory(p.join(_dataDir, 'workspaces', org, 'raw', 'sup', org))
          ..createSync(recursive: true);

    Copy.copyDir(rawOrgDir, rawOrgDirSup);

    final androidRuntimeSup =
        File(p.join(rawOrgDirSup.path, 'files', 'AndroidRuntime.jar'));

    final exe;
    if (Platform.isWindows) {
      exe = p.join(_dataDir, 'tools', 'jetifier-standalone', 'bin',
          'jetifier-standalone.bat');
    } else {
      exe = p.join(_dataDir, 'tools', 'jetifier-standalone', 'bin',
          'jetifier-standalone');
    }

    final args = <String>[exe];
    args
      ..addAll(['-i', androidRuntimeSup.path])
      ..addAll(['-o', androidRuntimeSup.path])
      ..add('-r');

    return args;
  }
}
