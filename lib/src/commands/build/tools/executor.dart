import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:rush/src/config/config.dart';

import 'package:rush/src/services/file_service.dart';
import 'package:rush/src/commands/build/tools/jdk_library.dart';
import 'package:rush/src/commands/build/utils.dart';
import 'package:rush/src/services/lib_service.dart';
import 'package:rush/src/services/ai2_runtime.dart';
import 'package:rush/src/utils/process_runner.dart';
import 'package:rush/src/utils/file_extension.dart';

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
    String? coreLibraryConfig,
  }) async {
    final desugared = '$output.d8.jar';
    await _runD8(
      minSdk: config.minSdk,
      input: input,
      output: desugared,
      classpathJars: classpathJars,
      classfileOutput: true,
      coreLibraryConfig: coreLibraryConfig,
    );
    await _correctInterfaceInitTriggers(input: desugared, output: output);
    await desugared.asFile().delete();
  }

  static Future<void> _correctInterfaceInitTriggers({
    required String input,
    required String output,
  }) =>
      _processRunner.runExecutable(
          BuildUtils.javaExe(),
          [
            '-cp',
            _libService.relocatorJar,
            'io.github.shreyashsaitwal.rush.relocator.DesugaredInterfaces',
            input,
            output,
          ].map((el) => el.replaceAll('\\', '/')).toList());

  static Future<void> _runD8({
    required int minSdk,
    required String input,
    required String output,
    required Set<String> classpathJars,
    bool classfileOutput = false,
    String? coreLibraryConfig,
  }) async =>
      _runR8Tool('com.android.tools.r8.D8', [
        if (classfileOutput) '--classfile',
        ...['--min-api', '$minSdk'],
        ...['--lib', (await Ai2Runtime.load()).androidJar],
        for (final jar in classpathJars) ...['--classpath', jar],
        if (coreLibraryConfig != null) ...[
          '--desugared-lib',
          coreLibraryConfig
        ],
        '--release',
        ...['--output', output],
        input,
      ]);

  static Future<void> execL8({
    required int minSdk,
    required String coreLibraryConfig,
    required String output,
  }) async =>
      _runR8Tool('com.android.tools.r8.L8', [
        '--classfile',
        ...['--min-api', '$minSdk'],
        ...['--lib', (await Ai2Runtime.load()).androidJar],
        ...['--desugared-lib', coreLibraryConfig],
        ...['--output', output],
        await _libService.coreLibraryJar(),
      ]);

  static Future<void> execTraceReferences({
    required Iterable<String> sources,
    required String target,
    required String output,
  }) async =>
      _runR8Tool('com.android.tools.r8.tracereferences.TraceReferences', [
        '--keep-rules',
        ...['--map-diagnostics:MissingDefinitionsDiagnostic', 'error', 'none'],
        ...['--lib', (await Ai2Runtime.load()).androidJar],
        for (final source in sources) ...['--source', source],
        ...['--target', target],
        ...['--output', output],
      ]);

  static Future<void> execR8Shrink({
    required String input,
    required Set<String> rules,
    required String output,
  }) async =>
      _runR8Tool('com.android.tools.r8.R8', [
        '--classfile',
        ...['--lib', (await Ai2Runtime.load()).androidJar],
        for (final el in rules) ...['--pg-conf', el],
        ...['--output', output],
        input,
      ]);

  static Future<void> execAapt2Compile({
    required String resDir,
    required String output,
  }) async =>
      _processRunner.runExecutable(await _libService.aapt2Exe(),
          ['compile', '--dir', resDir, '-o', output]);

  static Future<void> execAapt2Link({
    required String manifest,
    required String compiledResources,
    required String librarySymbols,
    required String symbols,
    required String output,
  }) async =>
      _processRunner.runExecutable(await _libService.aapt2Exe(), [
        'link',
        '--static-lib',
        '--non-final-ids',
        ...['-I', (await Ai2Runtime.load()).androidJar],
        ...['--manifest', manifest],
        ...['--auto-add-overlay', '-R', librarySymbols],
        ...['--output-text-symbols', symbols],
        ...['-o', output],
        compiledResources,
      ]);

  static Future<void> execJavac({
    required Set<String> sources,
    required String output,
  }) =>
      _processRunner.runExecutable(BuildUtils.javaExe(true),
          ['--release', '8', '-d', output, ...sources]);

  static Future<void> _runR8Tool(String mainClass, List<String> args,
          {bool debugStdout = false}) async =>
      _processRunner.runExecutable(
          BuildUtils.javaExe(),
          [
            ...['-cp', await _libService.r8Jar()],
            mainClass,
            ...args,
          ].map((el) => el.replaceAll('\\', '/')).toList(),
          debugStdout: debugStdout);

  static Future<void> execRelocator({
    required String input,
    required String output,
    required String spec,
  }) =>
      _processRunner.runExecutable(
          BuildUtils.javaExe(),
          ['-jar', _libService.relocatorJar, input, output, spec]
              .map((el) => el.replaceAll('\\', '/'))
              .toList());

  static Future<void> execR8(
    Iterable<String> program, {
    required String output,
    required Set<String> libraryJars,
    required Set<String> rules,
    required String mapping,
  }) async {
    await _runR8Tool(
      'com.android.tools.r8.R8',
      [
        '--classfile',
        '--pg-compat',
        ...['--lib', await jdkLibrary()],
        for (final jar in libraryJars) ...['--lib', jar],
        for (final rule in rules) ...['--pg-conf', rule],
        ...['--pg-map-output', mapping],
        ...['--output', output],
        ...program,
      ],
      debugStdout: true,
    );
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
      ...['--placeholder', 'applicationId=%packageName%'],
      ...['--out', output],
      ...['--log', 'INFO'],
    ];

    try {
      await _processRunner.runExecutable(BuildUtils.javaExe(),
          args.map((el) => el.replaceAll('\\', '/')).toList(),
          debugLines: RegExp('^ProGuard, version '));
    } catch (e) {
      rethrow;
    }
  }
}
