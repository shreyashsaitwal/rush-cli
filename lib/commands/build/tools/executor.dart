import 'dart:io' show Directory, File;

import 'package:path/path.dart' as p;
import 'package:rush_cli/commands/build/utils/build_utils.dart';
import 'package:rush_cli/commands/build/models/rush_lock/rush_lock.dart';
import 'package:rush_cli/commands/build/models/rush_yaml/rush_yaml.dart';
import 'package:rush_cli/utils/cmd_utils.dart';
import 'package:rush_cli/utils/process_streamer.dart';
import 'package:rush_cli/services/file_service.dart';

enum ExeType { d8, proguard }

class Executor {
  /// Executes the D8 tool which is required for dexing the extension.
  static Future<void> execD8(FileService fs) async {
    final args = () {
      final d8 = File(p.join(fs.toolsDir, 'other', 'd8.jar'));
      final rawDir = Directory(p.join(fs.buildDir, 'raw'));

      final res = [
        'java',
        ...['-cp', d8.path],
        'com.android.tools.r8.D8',
        ...['--lib', p.join(fs.devDepsDir, 'android.jar')],
        '--release',
        '--no-desugaring',
        '--output',
        p.join(rawDir.path, 'classes.jar'),
        p.join(rawDir.path, 'files', 'AndroidRuntime.jar'),
      ];
      return res;
    }();

    final result = await ProcessStreamer.stream(args, fs.cwd);
    if (!result.success) {
      throw Exception();
    }
  }

  /// Executes ProGuard which is used to optimize and obfuscate the code.
  static Future<void> execProGuard(
    FileService fs,
    RushYaml rushYaml,
    RushLock? rushLock,
  ) async {
    final args = () {
      final proguardJar = File(p.join(fs.toolsDir, 'other', 'proguard.jar'));

      final libraryJars =
          BuildUtils.classpathStringForDeps(fs, rushYaml, rushLock);

      final injar = File(p.join(fs.buildDir, 'ART.jar'));
      final outjar = File(p.join(fs.buildDir, 'ART.opt.jar'));

      final pgRules = File(p.join(fs.srcDir, 'proguard-rules.pro'));

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

    final result = await ProcessStreamer.stream(args, fs.cwd);
    if (!result.success) {
      throw Exception();
    }
  }

  /// Executes the rush-resolver.jar.
  static Future<void> execResolver(FileService fs) async {
    final classpath = CmdUtils.classpathString([
      Directory(p.join(fs.toolsDir, 'resolver')),
      Directory(p.join(fs.toolsDir, 'processor')),
      Directory(p.join(fs.devDepsDir)),
      File(p.join(fs.toolsDir, 'kotlinc', 'lib', 'kotlin-reflect.jar'))
    ]);

    final res = await ProcessStreamer.stream([
      'java',
      ...['-cp', classpath],
      'io.shreyash.rush.resolver.MainKt',
      fs.cwd,
    ], fs.cwd, printNormalOutput: true);

    if (!res.success) {
      throw Exception();
    }
  }

  static Future<void> execManifMerger(
    FileService fs,
    int minSdk,
    String mainManifest,
    List<String> depManifests,
  ) async {
    final classpath = CmdUtils.classpathString([
      Directory(p.join(fs.toolsDir, 'merger')),
      Directory(p.join(fs.devDepsDir, 'kotlin')),
      File(p.join(fs.devDepsDir, 'android.jar')),
      File(p.join(fs.devDepsDir, 'gson-2.1.jar')),
    ]);
    final output = p.join(fs.buildDir, 'files', 'MergedManifest.xml');

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
        await ProcessStreamer.stream(args, fs.cwd, printNormalOutput: true);
    if (!res.success) {
      throw Exception();
    }
  }
}
