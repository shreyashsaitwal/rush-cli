import 'dart:io' show Directory, File, Platform;

import 'package:path/path.dart' as p;
import 'package:rush_cli/commands/build/helpers/build_utils.dart';
import 'package:rush_cli/commands/build/models/rush_lock/rush_lock.dart';
import 'package:rush_cli/commands/build/models/rush_yaml/rush_yaml.dart';
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
        ..addAll(['--lib', p.join(_dataDir, 'dev-deps', 'android.jar')])
        ..addAll([
          '--release',
          '--output',
          p.join(rawPath, 'classes.jar'),
          p.join(rawPath, 'files', 'AndroidRuntime.jar'),
        ]);

      return res;
    }();

    final result = await ProcessStreamer.stream(args, _cd);
    if (result.result == Result.error) {
      throw Exception();
    }
  }

  /// Executes ProGuard which is used to optimize and obfuscate the code.
  Future<void> execProGuard(
      String org, BuildStep step, RushYaml rushYaml, RushLock? rushLock) async {
    final args = () {
      final proguardJar =
          File(p.join(_dataDir, 'tools', 'other', 'proguard.jar'));

      final libraryJars =
          BuildUtils.classpathStringForDeps(_cd, _dataDir, rushYaml, rushLock);
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

    final result = await ProcessStreamer.stream(args, _cd);
    if (result.result == Result.error) {
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

    final result =
        await ProcessStreamer.stream(args, _cd, patternChecker: patternChecker);
    if (result.result == Result.error) {
      throw Exception();
    }

    // If the above pattern exists, de-jetification isn't needed.
    return !patternChecker.patternExists;
  }

  /// Executes the rush-resolver.jar.
  Future<void> execResolver() async {
    final classpath = CmdUtils.classpathString([
      Directory(p.join(_dataDir, 'tools', 'resolver')),
      Directory(p.join(_dataDir, 'tools', 'processor')),
      Directory(p.join(_dataDir, 'dev-deps')),
      File(p.join(_dataDir, 'tools', 'kotlinc', 'lib', 'kotlin-reflect.jar'))
    ]);

    final res = await ProcessStreamer.stream([
      'java',
      ...['-cp', classpath],
      'io.shreyash.rush.resolver.MainKt',
      _cd,
    ], _cd, printNormalOutput: true);

    if (res.result == Result.error) {
      throw Exception();
    }
  }

  Future<void> execManifMerger(int minSdk, String mainManifest,
      List<String> depManifests, String output) async {
    final classpath = CmdUtils.classpathString([
      Directory(p.join(_dataDir, 'tools', 'merger')),
      Directory(p.join(_dataDir, 'dev-deps', 'kotlin')),
      File(p.join(_dataDir, 'dev-deps', 'android.jar')),
      File(p.join(_dataDir, 'dev-deps', 'gson-2.1.jar')),
    ]);

    final args = [
      'java',
      ...['-cp', classpath],
      'com.android.manifmerger.Merger',
      ...['--main', mainManifest],
      ...['--libs', depManifests.join(CmdUtils.cpSeparator())],
      ...['--property', 'MIN_SDK_VERSION=${minSdk.toString()}'],
      ...['--out', output],
      ...['--log', 'INFO'],
    ];

    final res =
        await ProcessStreamer.stream(args, _cd, printNormalOutput: true);
    if (res.result == Result.error) {
      throw Exception();
    }
  }
}
