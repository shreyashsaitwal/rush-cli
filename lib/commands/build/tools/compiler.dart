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

  static Future<void> compileJavaFiles(Set<String> depJars, bool supportJava8) async {
    final args = await _javacArgs(depJars, supportJava8);
    try {
      await _fs.javacArgsFile.writeAsString(args.join('\n'));
      await _processRunner
          .runExecutable('javac', ['@${_fs.javacArgsFile.path}']);
    } catch (e) {
      rethrow;
    }
  }

  static Future<List<String>> _javacArgs(Set<String> depJars, bool supportJava8) async {
    final classpath = depJars.join(BuildUtils.cpSeparator);
    final javaFiles = _fs.srcDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((el) => p.extension(el.path) == '.java')
        .map((el) => el.path);

    final args = <String>[
      ...['-source', supportJava8 ? '1.8' : '1.7'],
      ...['-target', supportJava8 ? '1.8' : '1.7'],
      ...['-encoding', 'UTF8'],
      ...['-d', _fs.buildClassesDir.path],
      ...['-cp', classpath],
      ...['-processorpath', _fs.processorJar.path],
      ...javaFiles,
    ];
    return args.map((el) => el.replaceAll('\\', '/')).toList();
  }

  static Future<void> compileKtFiles(
      Set<String> depJars, String kotlinVersion) async {
    try {
      final kotlincArgs = await _kotlincArgs(depJars, kotlinVersion);
      await _processRunner.runExecutable('java', kotlincArgs);
    } catch (e) {
      rethrow;
    }
  }

  static Future<List<String>> _kotlincArgs(
      Set<String> depJars, String kotlinVersion) async {
    // Here, we are copying the kotlin-annotation-processing-embeddable jar
    // in the it's own directory but with name: kotlin-annotation-processing.jar
    // This is a bug in kapt, and for more details:
    // https://youtrack.jetbrains.com/issue/KTIJ-22605/kotlin-annotation-processing-embeddable-isnt-actually-embeddable
    final kaptJar = _libService.kotlinAnnotationProc(kotlinVersion).first;
    final duplicateKaptJar =
        p.join(p.dirname(kaptJar), 'kotlin-annotation-processing.jar');
    kaptJar.asFile().copySync(duplicateKaptJar);

    final pluginPrefix = '-P=plugin:org.jetbrains.kotlin.kapt3';
    final kaptCliCp = [
      ..._libService.kotlincJars(kotlinVersion),
      ..._libService.kotlinAnnotationProc(kotlinVersion),
      // TODO: Consider using JDK bundled tools.jar or similar
      _fs.jreToolsJar.path,
    ].join(BuildUtils.cpSeparator);

    return <String>[
      // This -cp flag belongs to the java cmdline tool, required to run the
      // below KaptCli class
      ...['-cp', kaptCliCp],
      'org.jetbrains.kotlin.kapt.cli.KaptCli',
      // And this -cp flag belongs to the above KaptCli class
      ...['-cp', depJars.join(BuildUtils.cpSeparator)],
      '-Xplugin=$kaptJar',
      ...[
        '$pluginPrefix:classes=${_fs.buildKaptDir.path}',
        '$pluginPrefix:sources=${_fs.buildKaptDir.path}',
        '$pluginPrefix:stubs=${_fs.buildKaptDir.path}',
        '$pluginPrefix:apclasspath=${_fs.processorJar.path}',
      ],
      ...['-d', _fs.buildClassesDir.path],
      '-no-stdlib',
      _fs.srcDir.path,
    ].map((el) => el.replaceAll('\\', '/')).toList();
  }
}
