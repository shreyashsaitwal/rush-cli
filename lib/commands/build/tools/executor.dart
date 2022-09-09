import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/utils/file_extension.dart';
import 'package:rush_cli/utils/process_runner.dart';
import 'package:rush_cli/services/file_service.dart';

import '../../../services/libs_service.dart';
import '../utils.dart';

class Executor {
  static final _fs = GetIt.I<FileService>();
  static final _libService = GetIt.I<LibService>();
  static final processRunner = ProcessRunner();

  static Future<void> execD8(String artJarPath) async {
    final args = <String>[
      ...['-cp', _libService.d8Jar()],
      'com.android.tools.r8.D8',
      ...['--lib', p.join(_fs.libsDir.path, 'android.jar')],
      '--release',
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
      String artJarPath, Set<String> depJars) async {
    final rulesPro = p.join(_fs.srcDir.path, 'proguard-rules.pro').asFile();
    final optimizedJar =
        p.join(p.dirname(artJarPath), 'AndroidRuntime.optimized.jar').asFile();

    final args = <String>[
      ...['-cp', _libService.pgJars().join(BuildUtils.cpSeparator)],
      'proguard.ProGuard',
      ...['-injars', artJarPath],
      ...['-outjars', optimizedJar.path],
      ...['-libraryjars', depJars.join(BuildUtils.cpSeparator)],
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
    Iterable<String> depManifests,
  ) async {
    final classpath = <String>[
      ..._libService.manifMergerJars(),
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
      String artJarPath, Set<String> depJars) async {
    final outputJar = p
        .join(_fs.buildRawDir.path, 'files', 'AndroidRuntime.desugared.jar')
        .asFile();

    final desugarerArgs = <String>[
      '--desugar_try_with_resources_if_needed',
      '--copy_bridges_from_classpath',
      ...['--bootclasspath_entry', '\'${_fs.jreRtJar.path}\''],
      ...['--input', '\'$artJarPath\''],
      ...['--output', '\'${outputJar.path}\''],
      ...depJars.map((dep) => '--classpath_entry' '\n' '\'$dep\''),
    ];
    final argsFile =
        p.join(_fs.buildFilesDir.path, 'desugar.args').asFile(true);
    await argsFile.writeAsString(desugarerArgs.join('\n'));

    final args = <String>[
      ...['-cp', p.join(_fs.desugarJar.path)],
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
