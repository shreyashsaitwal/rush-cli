import 'dart:io' show Directory, File, Platform;

import 'package:path/path.dart' as p;
import 'package:rush_cli/helpers/cmd_utils.dart';
import 'package:rush_cli/helpers/process_streamer.dart';
import 'package:rush_prompt/rush_prompt.dart';
import 'package:process_runner/process_runner.dart' show ProcessRunnerException;

enum ExeType { d8, d8ForSup, proguard, jetifier }

class Executor {
  final String _cd;
  final String _dataDir;

  Executor(this._cd, this._dataDir);

  /// Executes the D8 tool which is required for dexing the extension.
  Future<void> execD8(String org, BuildStep step, {bool deJet = false}) async {
    final args = () {
      final d8 = File(p.join(_dataDir, 'tools', 'other', 'd8.jar'));

      final rawOrgDirX =
          Directory(p.join(_dataDir, 'workspaces', org, 'raw', 'x', org));
      final rawOrgDirSup =
          Directory(p.join(_dataDir, 'workspaces', org, 'raw', 'sup', org));

      final rawPath = deJet ? rawOrgDirSup.path : rawOrgDirX.path;

      final res = <String>['java'];

      res
        ..addAll(['-cp', d8.path])
        ..add('com.android.tools.r8.D8')
        ..addAll(['--lib', p.join(_cd, '.rush', 'dev-deps', 'android.jar')])
        ..addAll([
          '--release',
          '--output',
          p.join(rawPath, 'classes.jar'),
          p.join(rawPath, 'files', 'AndroidRuntime.jar'),
        ]);

      return res;
    };

    final stream = ProcessStreamer.stream(args());

    try {
      // ignore: unused_local_variable
      await for (final result in stream) {}
    } on ProcessRunnerException catch (e) {
      final errList = e.result!.stderr.split('\n');
      _prettyPrintErrors(errList, step);

      rethrow;
    }
  }

  /// Executes ProGuard which is used to optimize and obfuscate the code.
  Future<void> execProGuard(String org, BuildStep step) async {
    final args = () {
      final proguardJar =
          File(p.join(_dataDir, 'tools', 'other', 'proguard.jar'));

      final devDeps = Directory(p.join(_cd, '.rush', 'dev-deps'));
      final deps = Directory(p.join(_cd, 'deps'));

      final libraryJars = CmdUtils.generateClasspath([devDeps, deps]);

      final classesDir =
          Directory(p.join(_dataDir, 'workspaces', org, 'classes'));

      final injar = File(p.join(classesDir.path, 'ART.jar'));
      final outjar = File(p.join(classesDir.path, 'art_opt.jar'));

      final pgRules = File(p.join(_cd, 'src', 'proguard-rules.pro'));

      final res = <String>['java', '-jar', proguardJar.path];
      res
        ..addAll(['-injars', injar.path])
        ..addAll(['-outjars', outjar.path])
        ..addAll(['-libraryjars', libraryJars])
        ..add('@${pgRules.path}');

      return res;
    };

    final stream = ProcessStreamer.stream(args());

    try {
      // ignore: unused_local_variable
      await for (final result in stream) {}
    } on ProcessRunnerException catch (e) {
      final errList = e.result!.stderr.split('\n');
      _prettyPrintErrors(errList, step);

      rethrow;
    }
  }

  /// Executes Jetifier standalone in reverse mode. Returns true if de-jetification
  /// (androidx -> support lib) is required, otherwise false.
  Future<bool> execJetifier(String org, BuildStep step) async {
    final args = () {
      final rawOrgDir =
          Directory(p.join(_dataDir, 'workspaces', org, 'raw', 'x', org));
      final rawOrgDirSup =
          Directory(p.join(_dataDir, 'workspaces', org, 'raw', 'sup', org))
            ..createSync(recursive: true);

      CmdUtils.copyDir(rawOrgDir, rawOrgDirSup);

      final androidRuntimeSup =
          File(p.join(rawOrgDirSup.path, 'files', 'AndroidRuntime.jar'));

      final exe = p.join(_dataDir, 'tools', 'jetifier-standalone', 'bin',
          'jetifier-standalone' + (Platform.isWindows ? '.bat' : ''));

      final res = <String>[exe];
      res
        ..addAll(['-i', androidRuntimeSup.path])
        ..addAll(['-o', androidRuntimeSup.path])
        ..add('-r');

      return res;
    };

    final stream = ProcessStreamer.stream(args());

    var isDeJetNeeded = true;

    try {
      final pattern =
          RegExp(r'WARNING: \[Main\] No references were rewritten.');

      await for (final result in stream) {
        if (isDeJetNeeded) {
          isDeJetNeeded = !result.output.contains(pattern);
        }
      }
    } on ProcessRunnerException catch (e) {
      final errList = e.result!.stderr.split('\n');
      _prettyPrintErrors(errList, step);

      rethrow;
    }

    return isDeJetNeeded;
  }

  Future<void> execDesugar(String org, BuildStep step) async {
    final desugarJar = p.join(_dataDir, 'tools', 'other', 'desugar.jar');

    final inputJar =
        File(p.join(_dataDir, 'workspaces', org, 'classes', 'ART.jar'));
    final outputJar =
        File(p.join(_dataDir, 'workspaces', org, 'classes', 'ART.jar.dsgr'));

    final rtJar = p.join(_dataDir, 'tools', 'other', 'rt.jar');

    final fileContents = <String>[]
      // ignore: prefer_inlined_adds
      ..add('--emit_dependency_metadata_as_needed')
      ..addAll(['--bootclasspath_entry', rtJar])
      ..addAll(['--input', inputJar.path])
      ..addAll(['--output', outputJar.path]);

    final devDeps = Directory(p.join(_cd, '.rush', 'dev-deps'));
    final deps = Directory(p.join(_cd, 'deps'));
    final classpath =
        CmdUtils.generateClasspath([devDeps, deps], relative: false);

    classpath.split(CmdUtils.getSeparator()).forEach((el) {
      fileContents.addAll(['--classpath_entry', '\'' + el + '\'']);
    });

    final argsFile =
        File(p.join(_dataDir, 'workspaces', org, 'files', 'desugar.rsh'))
          ..createSync();

    var lines = '';
    fileContents.forEach((el) {
      lines += el + '\n';
    });
    argsFile.writeAsStringSync(lines);

    final args = <String>['java'];
    args
      ..addAll(['-cp', desugarJar])
      ..add('com.google.devtools.build.android.desugar.Desugar')
      ..add('@${argsFile.path}');

    final process = ProcessStreamer.stream(args);

    try {
      // ignore: unused_local_variable
      await for (final res in process) {}
    } on ProcessRunnerException catch (e) {
      _prettyPrintErrors(e.result!.stderr.split('\n'), step);
      rethrow;
    }

    inputJar.deleteSync();
    outputJar.renameSync(inputJar.path);
  }

  /// Analyzes [errList] and prints it accordingly to stdout/stderr in
  /// different colors.
  void _prettyPrintErrors(List<String> errList, BuildStep step) {
    final errPattern = RegExp(r'\s*error:?\s?', caseSensitive: false);
    final warnPattern = RegExp(r'\s*warning:?\s?', caseSensitive: false);
    final infoPattern = RegExp(r'\s*info:?\s?', caseSensitive: false);
    final notePattern = RegExp(r'\s*note:?\s?', caseSensitive: false);

    var prevLogType = LogType.erro;

    for (final err in errList) {
      if (err.startsWith(errPattern)) {
        final msg = err.replaceFirst(errPattern, '').trim();
        prevLogType = LogType.erro;

        step.log(LogType.erro, msg);
      } else if (err.startsWith(warnPattern)) {
        final msg = err.replaceFirst(warnPattern, '').trim();
        prevLogType = LogType.warn;

        step.log(LogType.warn, msg);
      } else if (err.startsWith(infoPattern)) {
        final msg = err.replaceFirst(infoPattern, '').trim();
        prevLogType = LogType.info;

        step.log(LogType.info, msg);
      } else if (err.startsWith(notePattern)) {
        final msg = err.replaceFirst(notePattern, '').trim();
        prevLogType = LogType.note;

        step.log(LogType.note, msg);
      } else {
        final msg = err.replaceFirst(errPattern, '').trim();
        step.log(prevLogType, ' ' * 7 + msg, addPrefix: false);
      }
    }
  }
}
