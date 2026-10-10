import 'dart:io' show File;

import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:get_it/get_it.dart';

import 'package:rush/src/services/logger.dart';
import 'package:rush/src/utils/file_extension.dart';
import 'package:rush/src/utils/process_runner.dart';
import 'package:rush/src/services/file_service.dart';
import 'package:rush/src/services/lib_service.dart';
import 'package:rush/src/commands/build/utils.dart';

const helpersTimestampKey = 'helper-enums';

class Compiler {
  static final _fs = GetIt.I<FileService>();
  static final _libService = GetIt.I<LibService>();
  static final _lgr = GetIt.I<Logger>();

  static final _processRunner = ProcessRunner();

  static Future<void> _compileHelpers(
    Set<String> classpathJars,
    LazyBox<DateTime> timestampBox, {
    String? ktVersion,
  }) async {
    // Only the files that reside directly under the "com.sth.helpers" package
    // are considered as helpers. We could probably lift this restriction in
    // future, but because this how AI2 does it, we'll stick to it for now.
    final helperFiles = _fs.srcDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((el) => el.path.split(p.separator).contains('helpers'));

    final helpersModTime = await timestampBox.get(helpersTimestampKey);
    final helpersModified = helpersModTime == null
        ? true
        : helperFiles
            .any((el) => el.lastModifiedSync().isAfter(helpersModTime));
    if (helperFiles.isEmpty || !helpersModified) {
      return;
    }

    _lgr.info('Pre-compiling helper enums...');
    final hasKtFiles = helperFiles.any((el) => p.extension(el.path) == '.kt');

    final helperPaths = helperFiles.map((e) => e.path).toSet();
    final compilationStartedOn = DateTime.now();
    if (hasKtFiles) {
      await _kotlinc(classpathJars, ktVersion!, helperPaths);
    } else {
      await _processRunner.runExecutable(BuildUtils.javaExe(true),
          await _javacArgs(helperPaths, classpathJars, withProc: false));
    }

    await _cleanUpOldClassFiles(compilationStartedOn, keepHelpers: true);
    await timestampBox.put(helpersTimestampKey, DateTime.now());
  }

  static Future<void> _cleanUpOldClassFiles(DateTime compilationStartedOn,
      {bool keepHelpers = false}) async {
    final files = _fs.buildClassesDir
        .listSync(recursive: true)
        .where((el) => p.extension(el.path) == '.class' && !keepHelpers
            ? !el.path.split(p.separator).contains('helpers')
            : true)
        .whereType<File>();

    for (final file in files) {
      if ((await file.lastModified()).isBefore(compilationStartedOn)) {
        await file.delete();
      }
    }
  }

  static Future<void> compileJavaFiles(
    Set<String> classpathJars,
    LazyBox<DateTime> timestampBox,
  ) async {
    final javaFiles = _fs.srcDir
        .listSync(recursive: true)
        .where((el) => el is File && p.extension(el.path) == '.java')
        .map((el) => el.path)
        .toSet();

    final DateTime compilationStartedOn;
    try {
      await _compileHelpers(classpathJars, timestampBox);
      final args = _javacArgs(javaFiles, classpathJars);
      compilationStartedOn = DateTime.now();
      await _processRunner.runExecutable(BuildUtils.javaExe(true), await args);
    } catch (e) {
      rethrow;
    }
    await _cleanUpOldClassFiles(compilationStartedOn);
  }

  static Future<List<String>> _javacArgs(
    Set<String> files,
    Set<String> classpathJars, {
    bool withProc = true,
  }) async {
    final classpath = classpathJars.join(BuildUtils.cpSeparator);
    final procClasspath = _libService.processorJar;
    final args = <String>[
      ...['--release', '8'],
      ...['-encoding', 'UTF8'],
      ...['-d', '"${_fs.buildClassesDir.path}"'],
      ...['-cp', '"$classpath"'],
      if (withProc) ...['-processorpath', '"$procClasspath"'],
      ...files.map((el) => '"$el"'),
    ].map((el) => el.replaceAll('\\', '/')).join('\n');
    await _fs.javacArgsFile.writeAsString(args);
    return ['@${_fs.javacArgsFile.path}'];
  }

  static Future<void> compileKtFiles(
    Set<String> classpathJars,
    String kotlinVersion,
    LazyBox<DateTime> timestampBox,
  ) async {
    await _compileHelpers(classpathJars, timestampBox,
        ktVersion: kotlinVersion);
    final compilationStartedOn = DateTime.now();
    await _kapt(classpathJars, kotlinVersion);
    await _kotlinc(classpathJars, kotlinVersion, {_fs.srcDir.path});
    await _cleanUpOldClassFiles(compilationStartedOn);
  }

  static Future<void> _kapt(
      Set<String> classpathJars, String kotlinVersion) async {
    final kaptJars = await _libService.kaptJars(kotlinVersion);
    await _makeKaptPluginDiscoverableByKotlinc(kaptJars.first);

    await _runKotlinTool(
      mainClass: 'org.jetbrains.kotlin.kapt.cli.KaptCli',
      toolClasspath: {
        ...await _libService.kotlincJars(kotlinVersion),
        ...kaptJars,
      },
      argsFile: _fs.kaptArgsFile,
      args: [
        ...['-cp', classpathJars.join(BuildUtils.cpSeparator)],
        '-Kapt-mode=stubsAndApt',
        '-Kapt-stubs=${_fs.buildKaptDir.path}',
        '-Kapt-sources=${_fs.buildKaptDir.path}',
        '-Kapt-classes=${_fs.buildKaptDir.path}',
        '-Kapt-classpath=${_libService.processorJar}',
        '-Kapt-strip-metadata=true',
        '-no-stdlib',
        _fs.srcDir.path,
      ],
    );
  }

  static Future<void> _kotlinc(
    Set<String> classpathJars,
    String kotlinVersion,
    Set<String> sources,
  ) async =>
      _runKotlinTool(
        mainClass: 'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler',
        toolClasspath: await _libService.kotlincJars(kotlinVersion),
        argsFile: _fs.kotlincArgsFile,
        args: [
          ...['-cp', classpathJars.join(BuildUtils.cpSeparator)],
          '-no-stdlib',
          ...['-d', _fs.buildClassesDir.path],
          ...sources,
        ],
      );

  static Future<void> _makeKaptPluginDiscoverableByKotlinc(
      String kaptEmbeddableJar) async {
    final expected = p.join(
        p.dirname(kaptEmbeddableJar), 'kotlin-annotation-processing.jar');
    if (!await expected.asFile().exists()) {
      await kaptEmbeddableJar.asFile().copy(expected);
    }
  }

  static Future<void> _runKotlinTool({
    required String mainClass,
    required Set<String> toolClasspath,
    required File argsFile,
    required List<String> args,
  }) async {
    String normalize(String path) => path.replaceAll('\\', '/');
    await argsFile.writeAsString(args.map(normalize).join('\n'));
    await _processRunner.runExecutable(BuildUtils.javaExe(), [
      ...['-cp', normalize(toolClasspath.join(BuildUtils.cpSeparator))],
      mainClass,
      '@${normalize(argsFile.path)}',
    ]);
  }
}
