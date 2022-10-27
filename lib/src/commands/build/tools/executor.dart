import 'dart:io';

import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;

import 'package:rush_cli/src/services/file_service.dart';
import 'package:rush_cli/src/commands/build/utils.dart';
import 'package:rush_cli/src/utils/constants.dart';
import 'package:rush_cli/src/utils/file_extension.dart';
import 'package:rush_cli/src/utils/process_runner.dart';

class Executor {
  static final _fs = GetIt.I<FileService>();
  static final processRunner = ProcessRunner();

  static Future<void> execD8(String artJarPath, String r8Jar) async {
    final args = <String>[
      ...['-cp', r8Jar],
      'com.android.tools.r8.D8',
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
      await processRunner.runExecutable(
          'java', args.map((el) => el.replaceAll('\\', '/')).toList());
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> execProGuard(
    String artJarPath,
    Set<String> comptimeJars,
    String pgClasspath,
    Set<String> aarProguardRules,
  ) async {
    final rulesFile = p.join(_fs.srcDir.path, 'proguard-rules.pro').asFile();
    final optimizedJar =
        p.join(p.dirname(artJarPath), 'AndroidRuntime.optimized.jar').asFile();

    final args = <String>[
      ...['-cp', pgClasspath],
      'proguard.ProGuard',
      ...['-injars', artJarPath],
      ...['-outjars', optimizedJar.path],
      ...['-libraryjars', comptimeJars.join(BuildUtils.cpSeparator)],
      ...[for (final el in aarProguardRules) '-include $el'],
      '@${rulesFile.path}',
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

  static Future<void> execDesugarer(
    String desugarJar,
    String artJarPath,
    Iterable<String> comptimeDepJars,
  ) async {
    final outputJar = p
        .join(_fs.buildRawDir.path, 'files', 'AndroidRuntime.dsgr.jar')
        .asFile();

    final bootclasspath = await () async {
      final String javaExe;
      if (Platform.isWindows) {
        final res = await Process.run('where', ['java'], runInShell: true);
        javaExe = res.stdout.toString().trim();
      } else {
        final res = await Process.run('which', ['java'], runInShell: true);
        javaExe = res.stdout.toString().trim();
      }

      final forJdk8AndBelow = p
          .join(p.dirname(p.dirname(javaExe)), 'jre', 'lib', 'rt.jar')
          .asFile();
      if (forJdk8AndBelow.existsSync()) {
        return forJdk8AndBelow;
      }

      return p
          .join(p.dirname(p.dirname(javaExe)), 'jmods', 'java.base.jmod')
          .asFile();
    }();

    final desugarerArgs = <String>[
      '--desugar_try_with_resources_if_needed',
      '--copy_bridges_from_classpath',
      ...['--bootclasspath_entry', '\'${bootclasspath.path}\''],
      ...['--input', '\'$artJarPath\''],
      ...['--output', '\'${outputJar.path}\''],
      ...comptimeDepJars.map((dep) => '--classpath_entry' '\n' '\'$dep\''),
    ];
    final argsFile =
        p.join(_fs.buildFilesDir.path, 'desugar.args').asFile(true);
    await argsFile.writeAsString(desugarerArgs.join('\n'));

    final tempDir = p.join(_fs.buildFilesDir.path).asDir().createTempSync();
    final args = <String>[
      // Required on JDK 11 (>11.0.9.1)
      // https://github.com/bazelbuild/bazel/commit/cecb3f1650d642dc626d6f418282bd802c29f6d7
      '-Djdk.internal.lambda.dumpProxyClasses=${tempDir.path}',
      ...['-cp', desugarJar],
      'com.google.devtools.build.android.desugar.Desugar',
      '@${argsFile.path}',
    ];

    try {
      await processRunner.runExecutable('java', args);
    } catch (_) {
      rethrow;
    } finally {
      tempDir.deleteSync(recursive: true);
    }

    await outputJar.copy(artJarPath);
    await outputJar.delete();
  }
}
