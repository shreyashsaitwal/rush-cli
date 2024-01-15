import 'package:collection/collection.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/src/config/config.dart';

import 'package:rush_cli/src/services/file_service.dart';
import 'package:rush_cli/src/commands/build/utils.dart';
import 'package:rush_cli/src/services/lib_service.dart';
import 'package:rush_cli/src/utils/constants.dart';
import 'package:rush_cli/src/utils/file_extension.dart';
import 'package:rush_cli/src/utils/process_runner.dart';

class Executor {
  static final _fs = GetIt.I<FileService>();
  static final _libService = GetIt.I<LibService>();
  static final _processRunner = ProcessRunner();

  static Future<void> execD8(Config config, String artJarPath) async {
    final args = <String>[
      ...['-cp', await _libService.r8Jar()],
      'com.android.tools.r8.D8',
      ...['--min-api', '${config.minSdk}'],
      ...[
        '--lib',
        p.join(_fs.libsDir.path, 'android-$androidPlatformSdkVersion.jar')
      ],
      '--release',
      '--no-desugaring',
      '--output',
      p.join(_fs.buildRawDir.path, 'classes.jar'),
      artJarPath
    ];

    try {
      await _processRunner.runExecutable(BuildUtils.javaExe(),
          args.map((el) => el.replaceAll('\\', '/')).toList());
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> execProGuard(
    Config config,
    String artJarPath,
    Set<String> aarProguardRules,
  ) async {
    final rulesFile = p.join(_fs.srcDir.path, 'proguard-rules.pro').asFile();
    final optimizedJar =
        p.join(p.dirname(artJarPath), 'AndroidRuntime.optimized.jar').asFile();

    final pgJars = await _libService.pgJars();

    // Take only provided deps since compile and runtime scoped deps have already
    // been added to the art jar
    final providedDeps = await _libService.providedDependencies(config);
    final libraryJars = providedDeps
        .map((el) => el.classpathJars(providedDeps))
        .flattened
        .toSet();

    final args = <String>[
      ...['-cp', pgJars.join(BuildUtils.cpSeparator)],
      'proguard.ProGuard',
      ...['-injars', artJarPath],
      ...['-outjars', optimizedJar.path],
      ...['-libraryjars', libraryJars.join(BuildUtils.cpSeparator)],
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

  static Future<void> execManifMerger(
    int minSdk,
    String mainManifest,
    Set<String> depManifests,
  ) async {
    final classpath = <String>[
      ...await _libService.manifMergerJars(),
      p.join(_fs.libsDir.path, 'android-$androidPlatformSdkVersion.jar'),
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

  static Future<void> execDesugarer(String artJarPath, Config config) async {
    final outputJar = p
        .join(_fs.buildRawDir.path, 'files', 'AndroidRuntime.dsgr.jar')
        .asFile();

    final bootclasspath = await () async {
      final javaHome = await BuildUtils.javaHomeDir();
      final forJdk8AndBelow = p.join(javaHome, 'jre', 'lib', 'rt.jar').asFile();
      if (await forJdk8AndBelow.exists()) {
        return forJdk8AndBelow;
      }
      return p.join(javaHome, 'jmods', 'java.base.jmod').asFile();
    }();

    final providedDeps = await _libService.providedDependencies(config);
    final classpathJars = providedDeps
        .map((el) => el.classpathJars(providedDeps))
        .flattened
        .toSet();

    final desugarerArgs = <String>[
      '--desugar_try_with_resources_if_needed',
      '--copy_bridges_from_classpath',
      ...['--bootclasspath_entry', '\'${bootclasspath.path}\''],
      ...['--input', '\'$artJarPath\''],
      ...['--output', '\'${outputJar.path}\''],
      ...classpathJars.map((dep) => '--classpath_entry' '\n' '\'$dep\''),
      ...['--min_sdk_version', '${config.minSdk}'],
    ];
    final argsFile =
        p.join(_fs.buildFilesDir.path, 'desugar.args').asFile(true);
    await argsFile.writeAsString(desugarerArgs.join('\n'));

    final tempDir = await p.join(_fs.buildFilesDir.path).asDir().createTemp();
    final args = <String>[
      // Required on JDK 11 (>11.0.9.1)
      // https://github.com/bazelbuild/bazel/commit/cecb3f1650d642dc626d6f418282bd802c29f6d7
      '-Djdk.internal.lambda.dumpProxyClasses=${tempDir.path}',
      ...['-cp', await _libService.desugarJar()],
      'com.google.devtools.build.android.desugar.Desugar',
      '@${argsFile.path}',
    ];

    try {
      await _processRunner.runExecutable(BuildUtils.javaExe(), args);
    } catch (_) {
      rethrow;
    } finally {
      await tempDir.delete(recursive: true);
    }

    await outputJar.copy(artJarPath);
    await outputJar.delete();
  }
}
