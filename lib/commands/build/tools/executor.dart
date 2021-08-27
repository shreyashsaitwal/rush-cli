import 'dart:io' show Directory, File, Platform;

import 'package:path/path.dart' as p;
import 'package:rush_cli/commands/build/utils/build_utils.dart';
import 'package:rush_cli/commands/build/models/rush_lock/rush_lock.dart';
import 'package:rush_cli/commands/build/models/rush_yaml/rush_yaml.dart';
import 'package:rush_cli/helpers/cmd_utils.dart';
import 'package:rush_cli/helpers/process_streamer.dart';
import 'package:rush_cli/services/file_service.dart';
import 'package:rush_prompt/rush_prompt.dart';

enum ExeType { d8, d8ForSup, proguard, jetifier }

class Executor {
  final FileService _fs;

  Executor(this._fs);

  /// Executes the D8 tool which is required for dexing the extension.
  Future<void> execD8(String org, BuildStep step, {bool deJet = false}) async {
    final args = () {
      final d8 = File(p.join(_fs.toolsDir, 'other', 'd8.jar'));

      final rawOrgDirX =
          Directory(p.join(_fs.workspacesDir, org, 'raw', 'x', org));
      final rawOrgDirSup =
          Directory(p.join(_fs.workspacesDir, org, 'raw', 'sup', org));

      final rawPath = deJet ? rawOrgDirSup.path : rawOrgDirX.path;

      final res = [
        'java',
        ...['-cp', d8.path],
        'com.android.tools.r8.D8',
        ...['--lib', p.join(_fs.devDepsDir, 'android.jar')],
        '--release',
        '--output',
        p.join(rawPath, 'classes.jar'),
        p.join(rawPath, 'files', 'AndroidRuntime.jar'),
      ];
      return res;
    }();

    final result = await ProcessStreamer.stream(args, _fs.cwd);
    if (result.result == Result.error) {
      throw Exception();
    }
  }

  /// Executes ProGuard which is used to optimize and obfuscate the code.
  Future<void> execProGuard(
      String org, BuildStep step, RushYaml rushYaml, RushLock? rushLock) async {
    final args = () {
      final proguardJar = File(p.join(_fs.toolsDir, 'other', 'proguard.jar'));

      final libraryJars =
          BuildUtils.classpathStringForDeps(_fs, rushYaml, rushLock);
      final artDir = Directory(p.join(_fs.workspacesDir, org, 'art'));

      final injar = File(p.join(artDir.path, 'ART.jar'));
      final outjar = File(p.join(artDir.path, 'ART.opt.jar'));

      final pgRules = File(p.join(_fs.cwd, 'proguard-rules.pro'));

      final res = <String>[
        'java',
        ...['-jar', proguardJar.path],
        ...['-injars', injar.path],
        ...['-outjars', outjar.path],
        ...['-libraryjars', libraryJars],
        '@${pgRules.path}',
      ];
      return res;
    }();

    final result = await ProcessStreamer.stream(args, _fs.cwd);
    if (result.result == Result.error) {
      throw Exception();
    }
  }

  /// Executes Jetifier standalone in reverse mode. Returns true if de-jetification
  /// (androidx -> support lib) is required, otherwise false.
  Future<bool> execDeJetifier(String org, BuildStep step) async {
    final args = () {
      final rawOrgDir =
          Directory(p.join(_fs.workspacesDir, org, 'raw', 'x', org));
      final rawOrgDirSup =
          Directory(p.join(_fs.workspacesDir, org, 'raw', 'sup', org))
            ..createSync(recursive: true);

      CmdUtils.copyDir(rawOrgDir, rawOrgDirSup);

      final androidRuntimeSup =
          File(p.join(rawOrgDirSup.path, 'files', 'AndroidRuntime.jar'));

      final exe = p.join(_fs.toolsDir, 'jetifier-standalone', 'bin',
          'jetifier-standalone' + (Platform.isWindows ? '.bat' : ''));

      final res = <String>[
        exe,
        '-r',
        ...['-i', androidRuntimeSup.path],
        ...['-o', androidRuntimeSup.path],
      ];
      return res;
    }();

    final patternChecker = ProcessPatternChecker(
        RegExp(r'WARNING: \[Main\] No references were rewritten.'));

    final result = await ProcessStreamer.stream(args, _fs.cwd,
        patternChecker: patternChecker);
    if (result.result == Result.error) {
      throw Exception();
    }

    // If the above pattern exists, de-jetification isn't needed.
    return !patternChecker.patternExists;
  }

  /// Executes the rush-resolver.jar.
  Future<void> execResolver() async {
    final classpath = CmdUtils.classpathString([
      Directory(p.join(_fs.toolsDir, 'resolver')),
      Directory(p.join(_fs.toolsDir, 'processor')),
      Directory(p.join(_fs.devDepsDir)),
      File(p.join(_fs.toolsDir, 'kotlinc', 'lib', 'kotlin-reflect.jar'))
    ]);

    final res = await ProcessStreamer.stream([
      'java',
      ...['-cp', classpath],
      'io.shreyash.rush.resolver.MainKt',
      _fs.cwd,
    ], _fs.cwd, printNormalOutput: true);

    if (res.result == Result.error) {
      throw Exception();
    }
  }

  Future<void> execManifMerger(int minSdk, String mainManifest,
      List<String> depManifests, String output) async {
    final classpath = CmdUtils.classpathString([
      Directory(p.join(_fs.toolsDir, 'merger')),
      Directory(p.join(_fs.devDepsDir, 'kotlin')),
      File(p.join(_fs.devDepsDir, 'android.jar')),
      File(p.join(_fs.devDepsDir, 'gson-2.1.jar')),
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

    final res = await ProcessStreamer.stream(args, _fs.cwd,
        printNormalOutput: true);
    if (res.result == Result.error) {
      throw Exception();
    }
  }
}
