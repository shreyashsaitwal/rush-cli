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

  static Future<void> compile(
    Set<String> classpathJars, {
    required Set<String> javaFiles,
    required Set<String> kotlinFiles,
    required String kotlinVersion,
    required LazyBox<DateTime> timestampBox,
  }) async {
    await _compileHelpers(classpathJars, timestampBox, kotlinVersion);
    final startedOn = await _markCompilationStart();
    if (kotlinFiles.isNotEmpty) {
      await _kapt(classpathJars, kotlinVersion);
      await _kotlinc(classpathJars, kotlinVersion, {_fs.srcDir.path});
    }
    if (javaFiles.isNotEmpty) {
      await _javac(
        javaFiles,
        {...classpathJars, _fs.buildClassesDir.path},
        withProcessor: kotlinFiles.isEmpty,
      );
    }
    await _removeClassesOlderThan(startedOn);
  }

  static bool _isCompiled(File source) => p
      .join(
          _fs.buildClassesDir.path,
          p.setExtension(
              p.relative(source.path, from: _fs.srcDir.path), '.class'))
      .asFile()
      .existsSync();

  static Future<DateTime> _markCompilationStart() async {
    final marker = p.join(_fs.buildDir.path, 'compilation-start').asFile(true);
    await marker.writeAsString('');
    return marker.lastModified();
  }

  static Future<void> _compileHelpers(
    Set<String> classpathJars,
    LazyBox<DateTime> timestampBox,
    String kotlinVersion,
  ) async {
    // Only the files that reside directly under the "com.sth.helpers" package
    // are considered as helpers. We could probably lift this restriction in
    // future, but because this how AI2 does it, we'll stick to it for now.
    final helperFiles = _fs.srcDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((el) => el.path.split(p.separator).contains('helpers'));

    final helpersModTime = await timestampBox.get(helpersTimestampKey);
    final helpersModified = helpersModTime == null ||
        helperFiles.any((el) =>
            el.lastModifiedSync().isAfter(helpersModTime) || !_isCompiled(el));
    if (helperFiles.isEmpty || !helpersModified) {
      return;
    }

    _lgr.info('Pre-compiling helper enums...');
    final hasKtFiles = helperFiles.any((el) => p.extension(el.path) == '.kt');

    final helperPaths = helperFiles.map((e) => e.path).toSet();
    if (hasKtFiles) {
      await _kotlinc(classpathJars, kotlinVersion, helperPaths);
    } else {
      await _javac(helperPaths, classpathJars, withProcessor: false);
    }
    await timestampBox.put(helpersTimestampKey, DateTime.now());
  }

  static Future<void> _removeClassesOlderThan(DateTime startedOn) async {
    final stale = _fs.buildClassesDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) =>
            p.extension(file.path) == '.class' &&
            file.lastModifiedSync().isBefore(startedOn));
    for (final file in stale) {
      await file.delete();
    }
  }

  static Future<void> _javac(
    Set<String> files,
    Set<String> classpath, {
    required bool withProcessor,
  }) =>
      _runWithArgsFile(
        executable: BuildUtils.javaExe(true),
        argsFile: _fs.javacArgsFile,
        args: [
          ...['--release', '8'],
          ...['-encoding', 'UTF8'],
          ...['-d', _fs.buildClassesDir.path],
          ...['-cp', classpath.join(BuildUtils.cpSeparator)],
          if (withProcessor) ...['-processorpath', _libService.processorJar],
          ...files,
        ],
      );

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
  }) =>
      _runWithArgsFile(
        executable: BuildUtils.javaExe(),
        leadingArgs: [
          '-cp',
          _normalize(toolClasspath.join(BuildUtils.cpSeparator)),
          mainClass
        ],
        argsFile: argsFile,
        args: args,
      );

  static Future<void> _runWithArgsFile({
    required String executable,
    List<String> leadingArgs = const [],
    required File argsFile,
    required List<String> args,
  }) async {
    await argsFile
        .writeAsString(args.map((arg) => '"${_normalize(arg)}"').join('\n'));
    await _processRunner.runExecutable(
        executable, [...leadingArgs, '@${_normalize(argsFile.path)}']);
  }

  static String _normalize(String path) => path.replaceAll('\\', '/');
}
