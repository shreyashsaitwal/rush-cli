import 'dart:io' show Directory, File, Platform;

import 'package:path/path.dart' as p;
import 'package:rush_cli/helpers/cmd_utils.dart';
import 'package:rush_cli/helpers/process_streamer.dart';
import 'package:rush_prompt/rush_prompt.dart';

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
    }();

    final result =
        await ProcessStreamer.stream(args, _cd, step, isProcessIsolated: false);
    if (result == ProcessResult.error) {
      throw Exception();
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

      final artDir = Directory(p.join(_dataDir, 'workspaces', org, 'art'));

      final injar = File(p.join(artDir.path, 'ART.jar'));
      final outjar = File(p.join(artDir.path, 'ART.opt.jar'));

      final pgRules = File(p.join(_cd, 'src', 'proguard-rules.pro'));

      final res = <String>['java', '-jar', proguardJar.path];
      res
        ..addAll(['-injars', injar.path])
        ..addAll(['-outjars', outjar.path])
        ..addAll(['-libraryjars', libraryJars])
        ..add('@${pgRules.path}');

      return res;
    }();

    final result =
        await ProcessStreamer.stream(args, _cd, step, isProcessIsolated: false);
    if (result == ProcessResult.error) {
      throw Exception();
    }
  }

  /// Executes Jetifier standalone in reverse mode. Returns true if de-jetification
  /// (androidx -> support lib) is required, otherwise false.
  Future<bool> execDeJetifier(String org, BuildStep step) async {
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
    }();

    final patternChecker = ProcessPatternChecker(
        RegExp(r'WARNING: \[Main\] No references were rewritten.'));

    final stream = await ProcessStreamer.stream(args, _cd, step,
        isProcessIsolated: false, patternChecker: patternChecker);
    if (stream == ProcessResult.error) {
      throw Exception();
    }

    // If the above pattern exists, de-jetification isn't needed.
    return !patternChecker.patternExists;
  }
}
