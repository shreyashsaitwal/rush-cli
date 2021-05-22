import 'dart:io' show Directory, File, Platform;

import 'package:process_runner/process_runner.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/helpers/copy.dart';
import 'package:rush_cli/java/helper.dart';
import 'package:rush_prompt/rush_prompt.dart';

enum CmdType { d8, d8sup, proguard, jetifier }

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
      case CmdType.d8:
        args.addAll(_getD8Args(org, false));
        break;
      case CmdType.d8sup:
        args.addAll(_getD8Args(org, true));
        break;
      // case CmdType.jar:
      //   dwd = p.join(_dataDir, 'workspaces', org, 'classes');
      //   args.addAll(_getJarArgs(org, dwd));
      //   break;
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
      ..addAll(['--lib', p.join(_cd, '.rush', 'dev-deps', 'android.jar')])
      ..addAll([
        '--release',
        '--output',
        p.join(rawPath, 'classes.jar'),
        p.join(rawPath, 'files', 'AndroidRuntime.jar'),
      ]);

    return args;
  }

  /// Returns the args required for running ProGuard
  List<String> _getPgArgs(String org) {
    final proguardJar =
        File(p.join(_dataDir, 'tools', 'other', 'proguard.jar'));

    final devDeps = Directory(p.join(_cd, '.rush', 'dev-deps'));
    final deps = Directory(p.join(_cd, 'deps'));

    final libraryJars = Helper.generateClasspath([devDeps, deps]);

    final classesDir =
        Directory(p.join(_dataDir, 'workspaces', org, 'classes'));

    final injar = File(p.join(classesDir.path, 'art.jar'));
    final outjar = File(p.join(classesDir.path, 'art_opt.jar'));

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

    final exe = p.join(_dataDir, 'tools', 'jetifier-standalone', 'bin',
          'jetifier-standalone' + (Platform.isWindows ? '.bat' : ''));

    final args = <String>[exe];
    args
      ..addAll(['-i', androidRuntimeSup.path])
      ..addAll(['-o', androidRuntimeSup.path])
      ..add('-r');

    return args;
  }
}
