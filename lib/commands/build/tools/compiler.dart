import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:get_it/get_it.dart';
import 'package:rush_cli/utils/file_extension.dart';
import 'package:rush_cli/utils/process_runner.dart';
import 'package:rush_cli/services/file_service.dart';

import '../../../services/libs_service.dart';
import '../utils.dart';

class Compiler {
  static final _fs = GetIt.I<FileService>();
  static final _processRunner = ProcessRunner();
  static final _libService = GetIt.I<LibService>();

  static Future<void> _compilerHelpers(
    Iterable<String> depJars, {
    String? ktVersion,
    bool java8 = false,
  }) async {
    // Only the files that reside directly under the "com.sth.helpers" package
    // are considered as helpers. We could probably lift this restriction in
    // future, but because this how AI2 does it, we'll stick to it for now.
    final helperFiles = _fs.srcDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((el) => p.basename(el.parent.path) == 'helpers');

    if (helperFiles.isEmpty) {
      return;
    }

    print('Compiling helpers');
    final time = DateTime.now();

    final package =
        p.relative(helperFiles.first.parent.path, from: _fs.srcDir.path);
    final hasKtFiles = helperFiles.any((el) => p.extension(el.path) == '.kt');
    final outputDir = p.join(_fs.buildClassesDir.path, package);

    final List<String> args;
    if (hasKtFiles) {
      args = await _kotlincArgs(
          helperFiles.first.parent.path, depJars, ktVersion!,
          files: helperFiles.map((e) => e.path), withProc: false);
    } else {
      args = _javacArgs(helperFiles.map((e) => e.path), depJars, java8,
          withProc: false);
    }

    try {
      await _processRunner.runExecutable(hasKtFiles ? 'java' : 'javac', args);
    } catch (e) {
      rethrow;
    }

    print(DateTime.now().difference(time).inMilliseconds);
  }

  static Future<void> compileJavaFiles(
      Set<String> depJars, bool supportJava8) async {
    final javaFiles = _fs.srcDir
        .listSync(recursive: true)
        .where((el) => el is File && p.extension(el.path) == '.java')
        .map((el) => el.path);
    final args = _javacArgs(javaFiles, depJars, supportJava8);
    try {
      await _compilerHelpers(depJars, java8: supportJava8);
      await _processRunner.runExecutable('javac', args);
    } catch (e) {
      rethrow;
    }
  }

  static List<String> _javacArgs(
    Iterable<String> files,
    Iterable<String> depJars,
    bool supportJava8, {
    bool withProc = true,
  }) {
    final classpath = depJars.join(BuildUtils.cpSeparator);
    final args = <String>[
      ...['-source', supportJava8 ? '1.8' : '1.7'],
      ...['-target', supportJava8 ? '1.8' : '1.7'],
      ...['-encoding', 'UTF8'],
      ...['-d', _fs.buildClassesDir.path],
      ...['-cp', classpath],
      if (withProc) ...['-processorpath', _fs.processorJar.path],
      ...files,
    ].map((el) => el.replaceAll('\\', '/')).join('\n');
    _fs.javacArgsFile.writeAsStringSync(args);
    return ['@${_fs.javacArgsFile.path}'];
  }

  static Future<void> compileKtFiles(
      Set<String> depJars, String kotlinVersion) async {
    try {
      await _compilerHelpers(depJars, ktVersion: kotlinVersion);
      final kotlincArgs =
          await _kotlincArgs(_fs.srcDir.path, depJars, kotlinVersion);
      await _processRunner.runExecutable('java', kotlincArgs);
    } catch (e) {
      rethrow;
    }
  }

  static Future<List<String>> _kotlincArgs(
    String srcDir,
    Iterable<String> depJars,
    String kotlinVersion, {
    bool withProc = true,
    Iterable<String>? files,
  }) async {
    // Here, we are copying the kotlin-annotation-processing-embeddable jar
    // in the it's own directory but with name: kotlin-annotation-processing.jar
    // This is a bug in kapt, and for more details:
    // https://youtrack.jetbrains.com/issue/KTIJ-22605/kotlin-annotation-processing-embeddable-isnt-actually-embeddable
    final kaptJar = _libService.kaptJars(kotlinVersion).first;
    final duplicateKaptJar =
        p.join(p.dirname(kaptJar), 'kotlin-annotation-processing.jar');
    kaptJar.asFile().copySync(duplicateKaptJar);

    final classpath = [
      ..._libService.kotlincJars(kotlinVersion),
      if (withProc) ..._libService.kaptJars(kotlinVersion),
      // TODO: Consider using JDK bundled tools.jar or similar
      if (withProc) _fs.jreToolsJar.path,
    ].join(BuildUtils.cpSeparator);

    final kotlincArgs = <String>[
      ...['-cp', depJars.join(BuildUtils.cpSeparator)],
      if (withProc) ...[
        // KaptCli args
        '-Kapt-classes=${_fs.buildKaptDir.path}',
        '-Kapt-sources=${_fs.buildKaptDir.path}',
        '-Kapt-stubs=${_fs.buildKaptDir.path}',
        '-Kapt-classpath=${_fs.processorJar.path}',
        '-Kapt-mode=compile',
        '-Kapt-strip-metadata=true',
        '-Kapt-use-light-analysis=true',
      ],
      '-no-stdlib',
      ...['-d', _fs.buildClassesDir.path],
      if (files != null) ...files else srcDir,
    ].map((el) => el.replaceAll('\\', '/')).join('\n');
    final argsFile = _fs.kotlincArgsFile..writeAsStringSync(kotlincArgs);

    return <String>[
      // This -cp flag belongs to the java cmdline tool, required to run the
      // below KaptCli class
      ...['-cp', classpath],
      if (withProc)
        'org.jetbrains.kotlin.kapt.cli.KaptCli'
      else
        'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler',
      '@${argsFile.path}',
    ].map((el) => el.replaceAll('\\', '/')).toList();
  }
}
