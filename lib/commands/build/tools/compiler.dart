import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:get_it/get_it.dart';
import 'package:rush_cli/utils/process_runner.dart';
import 'package:rush_cli/services/file_service.dart';

import '../../../services/libs_service.dart';
import '../utils.dart';

// TODO
class Compiler {
  static final _fs = GetIt.I<FileService>();
  static final _processRunner = ProcessRunner();
  static final _libService = GetIt.I<LibService>();

  static Future<void> compileJavaFiles(Set<String> depJars) async {
    final args = await _javacArgs(depJars);
    try {
      await _fs.javacArgsFile.writeAsString(args.join('\n'));
      await _processRunner
          .runExecutable('javac', ['@${_fs.javacArgsFile.path}']);
    } catch (e) {
      rethrow;
    }
  }

  static Future<List<String>> _javacArgs(Set<String> depJars) async {
    final classpath = depJars.join(BuildUtils.cpSeparator);
    final procpath = [
      // _libService.kotlinStdLib(ktVersion: kotlinVersion),
      _fs.processorJar.path,
    ].join(BuildUtils.cpSeparator);

    final javaFiles = _fs.srcDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((el) => p.extension(el.path) == '.java')
        .map((el) => el.path);

    final args = <String>[
      ...['-target', '1.8'],
      ...['-encoding', 'UTF8'],
      ...['-d', _fs.buildClassesDir.path],
      ...['-cp', classpath],
      ...['-processorpath', procpath],
      ...javaFiles,
    ];

    return args.map((el) => el.replaceAll('\\', '/')).toList();
  }

  // TODO: Run kapt and compiler in parallel
  static Future<void> compileKtFiles(
      Set<String> depJars, String kotlinVersion) async {
    throw UnimplementedError('kotlin-compiler-embeddable');
    // final kotlincArgs = await _kotlincArgs(depJars);
    // try {
    //   await _fs.kotlincArgsFile.writeAsString(kotlincArgs.join('\n'));
    //   await _processRunner.runExecutable(
    //       _fs.kotlincScript.path, ['@${_fs.kotlincArgsFile.path}']);
    // } catch (e) {
    //   rethrow;
    // }

    // final kaptArgs = await _kaptArgs(depJars);
    // try {
    //   await _fs.kaptArgsFile.writeAsString(kaptArgs.join('\n'));
    //   await _processRunner
    //       .runExecutable(_fs.kotlincScript.path, ['@${_fs.kaptArgsFile.path}']);
    // } catch (e) {
    //   rethrow;
    // }
  }

  static Future<List<String>> _kotlincArgs(Set<String> depJars) async {
    final classpath = depJars.join(BuildUtils.cpSeparator);
    final args = <String>[
      ...['-d', _fs.buildClassesDir.path],
      ...['-cp', '"$classpath"'],
      _fs.srcDir.path,
    ];
    return args.map((el) => el.replaceAll('\\', '/')).toList();
  }

  static Future<List<String>> _kaptArgs(
      Set<String> depJars, String kotlinVersion) async {
    final classpath = depJars.join(BuildUtils.cpSeparator);
    final pluginPrefix = '-P "plugin:org.jetbrains.kotlin.kapt3:';

    final args = <String>[
      ...['-cp', '"$classpath"'],
      // TODO: Use jmod on jdk >8
      '-Xplugin="${_fs.jreToolsJar.path}"',
      ...[
        '-Xplugin="${_libService.kotlinAnnotationProc(kotlinVersion)}"',
        '${pluginPrefix}sources=${_fs.buildKaptDir.path}"',
        '${pluginPrefix}classes=${_fs.buildKaptDir.path}"',
        '${pluginPrefix}stubs=${_fs.buildKaptDir.path}"',
        '${pluginPrefix}aptMode=stubsAndApt"',
        '${pluginPrefix}apclasspath=${_fs.processorJar.path}"',
      ],
      _fs.srcDir.path,
    ];
    return args.map((el) => el.replaceAll('\\', '/')).toList();
  }
}
