import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:rush/src/config/config.dart';

import 'package:rush/src/services/file_service.dart';
import 'package:rush/src/commands/build/utils.dart';
import 'package:rush/src/services/lib_service.dart';
import 'package:rush/src/services/ai2_runtime.dart';
import 'package:rush/src/utils/file_extension.dart';
import 'package:rush/src/utils/process_runner.dart';

class Executor {
  static final _fs = GetIt.I<FileService>();
  static final _libService = GetIt.I<LibService>();
  static final _processRunner = ProcessRunner();

  static Future<void> execD8(
    Config config,
    String artJarPath,
    Set<String> classpathJars,
  ) =>
      _runD8(
        minSdk: config.minSdk,
        input: artJarPath,
        output: p.join(_fs.buildRawDir.path, 'classes.jar'),
        classpathJars: classpathJars,
      );

  static Future<void> execDesugar(
    Config config, {
    required String input,
    required String output,
    required Set<String> classpathJars,
  }) =>
      _runD8(
        minSdk: config.minSdk,
        input: input,
        output: output,
        classpathJars: classpathJars,
        classfileOutput: true,
      );

  static Future<void> _runD8({
    required int minSdk,
    required String input,
    required String output,
    required Set<String> classpathJars,
    bool classfileOutput = false,
  }) async {
    final args = <String>[
      ...['-cp', await _libService.r8Jar()],
      'com.android.tools.r8.D8',
      if (classfileOutput) '--classfile',
      ...['--min-api', '$minSdk'],
      ...['--lib', (await Ai2Runtime.load()).androidJar],
      for (final jar in classpathJars) ...['--classpath', jar],
      '--release',
      ...['--output', output],
      input,
    ];
    await _processRunner.runExecutable(BuildUtils.javaExe(),
        args.map((el) => el.replaceAll('\\', '/')).toList());
  }

  static Future<void> execProGuard(
    Config config,
    String artJarPath,
    Set<String> libraryJars,
    Set<String> aarProguardRules,
  ) async {
    final rulesFile = p.join(_fs.srcDir.path, 'proguard-rules.pro').asFile();
    final optimizedJar =
        p.join(p.dirname(artJarPath), 'AndroidRuntime.optimized.jar').asFile();

    final pgJars = await _libService.pgJars();

    final args = <String>[
      ...['-cp', pgJars.join(BuildUtils.cpSeparator)],
      'proguard.ProGuard',
      ...['-injars', artJarPath],
      ...['-outjars', optimizedJar.path],
      ...['-libraryjars', libraryJars.join(BuildUtils.cpSeparator)],
      for (final module in await _javaModules()) ...['-libraryjars', module],
      ...[for (final el in aarProguardRules) '-include $el'],
      '@${rulesFile.path}',
    ];

    try {
      await _processRunner.runExecutable(BuildUtils.javaExe(),
          args.map((el) => el.replaceAll('\\', '/')).toList());
    } catch (e) {
      rethrow;
    }

    await optimizedJar.copy(artJarPath);
    await optimizedJar.delete();
  }

  static Future<List<String>> _javaModules() async {
    final jmods = p.join(await BuildUtils.javaHomeDir(), 'jmods');
    return [
      for (final module in ['java.base', 'java.compiler'])
        '${p.join(jmods, '$module.jmod')}(!**.jar;!module-info.class)',
    ];
  }

  static Future<void> execManifMerger(
    int minSdk,
    String mainManifest,
    Set<String> depManifests,
  ) async {
    final classpath = <String>[
      ...await _libService.manifMergerJars(),
      (await Ai2Runtime.load()).androidJar,
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
      await _processRunner.runExecutable(BuildUtils.javaExe(),
          args.map((el) => el.replaceAll('\\', '/')).toList());
    } catch (e) {
      rethrow;
    }
  }
}
