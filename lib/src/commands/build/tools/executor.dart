import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;

import 'package:rush_cli/src/services/file_service.dart';
import 'package:rush_cli/src/commands/build/utils.dart';
import 'package:rush_cli/src/utils/file_extension.dart';
import 'package:rush_cli/src/utils/process_runner.dart';

class Executor {
  static final _fs = GetIt.I<FileService>();
  static final processRunner = ProcessRunner();

  static Future<void> execD8(String artJarPath, String r8Jar) async {
    final args = <String>[
      ...['-cp', r8Jar],
      'com.android.tools.r8.D8',
      ...['--lib', p.join(_fs.libsDir.path, 'android.jar')],
      '--release',
      '--intermediate',
      '--no-desugaring',
      '--output',
      p.join(_fs.buildRawDir.path, 'classes.jar'),
      artJarPath
    ];

    try {
      await processRunner.runExecutable(
          'java', args.map((el) => el.replaceAll('\\', '/')).toList());
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> execProGuard(
      String artJarPath, Set<String> comptimeJars, String pgClasspath) async {
    final rulesPro = p.join(_fs.srcDir.path, 'proguard-rules.pro').asFile();
    final optimizedJar =
        p.join(p.dirname(artJarPath), 'AndroidRuntime.optimized.jar').asFile();

    final args = <String>[
      ...['-cp', pgClasspath],
      'proguard.ProGuard',
      ...['-injars', artJarPath],
      ...['-outjars', optimizedJar.path],
      ...['-libraryjars', comptimeJars.join(BuildUtils.cpSeparator)],
      '@${rulesPro.path}',
    ];

    try {
      await processRunner.runExecutable(
          'java', args.map((el) => el.replaceAll('\\', '/')).toList());
    } catch (e) {
      rethrow;
    }

    await optimizedJar.copy(artJarPath);
    await optimizedJar.delete();
  }

  static Future<void> execManifMerger(
    int minSdk,
    String mainManifest,
    Set<String> depManifests,
    Iterable<String> manifMergerJars,
  ) async {
    final classpath = <String>[
      ...manifMergerJars,
      p.join(_fs.libsDir.path, 'android.jar'),
    ].join(BuildUtils.cpSeparator);

    final output = p.join(_fs.buildFilesDir.path, 'AndroidManifest.xml');
    final args = <String>[
      ...['-cp', classpath],
      'com.android.manifmerger.Merger',
      ...['--main', mainManifest],
      ...['--libs', depManifests.join(BuildUtils.cpSeparator)],
      ...['--property', 'MIN_SDK_VERSION=${minSdk.toString()}'],
      ...['--out', output],
      ...['--log', 'INFO'],
    ];

    try {
      await processRunner.runExecutable(
          'java', args.map((el) => el.replaceAll('\\', '/')).toList());
    } catch (e) {
      rethrow;
    }
  }

  // TODO: This can be execed on JDK >8, see here:
  // https://linear.app/shreyash/issue/RSH-51/toolsjar-and-rtjar-might-be-the-reason-for-desugaring-not-working-on
  static Future<void> execDesugarer(
      String desugarJar, String artJarPath, Set<String> comptimeDepJars) async {
    final outputJar = p
        .join(_fs.buildRawDir.path, 'files', 'AndroidRuntime.desugared.jar')
        .asFile();

    final desugarerArgs = <String>[
      '--desugar_try_with_resources_if_needed',
      '--copy_bridges_from_classpath',
      ...['--bootclasspath_entry', '\'${_fs.jreRtJar.path}\''],
      ...['--input', '\'$artJarPath\''],
      ...['--output', '\'${outputJar.path}\''],
      ...comptimeDepJars.map((dep) => '--classpath_entry' '\n' '\'$dep\''),
    ];
    final argsFile =
        p.join(_fs.buildFilesDir.path, 'desugar.args').asFile(true);
    await argsFile.writeAsString(desugarerArgs.join('\n'));

    final args = <String>[
      ...['-cp', desugarJar],
      'com.google.devtools.build.android.desugar.Desugar',
      '@${argsFile.path}',
    ];

    try {
      await processRunner.runExecutable('java', args);
    } catch (e) {
      rethrow;
    }

    await outputJar.copy(artJarPath);
    await outputJar.delete();
  }
}
