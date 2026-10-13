import 'dart:convert';
import 'dart:io' show Platform, Process;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;

import 'package:rush/src/services/file_service.dart';
import 'package:rush/src/services/logger.dart';
import 'package:rush/src/utils/file_extension.dart';
import 'package:rush/src/utils/zip.dart';

class BuildUtils {
  static final _fs = GetIt.I<FileService>();
  static final _lgr = GetIt.I<Logger>();

  static Future<void> unzip(String zipFilePath, String outputDirPath) async {
    final archive =
        ZipDecoder().decodeBytes(await zipFilePath.asFile().readAsBytes());
    for (final el in archive.files) {
      if (el.isFile) {
        final bytes = el.content as List<int>;
        try {
          final file = p.join(outputDirPath, el.name).asFile(true);
          await file.writeAsBytes(bytes);
        } catch (e) {
          _lgr.parseAndLog('error: $e');
          rethrow;
        }
      }
    }
  }

  static Future<Uint8List> zipReplacingEntry({
    required String source,
    required String entry,
    required String replacement,
  }) async {
    final original =
        ZipDecoder().decodeBytes(await source.asFile().readAsBytes());
    final replacementBytes = await replacement.asFile().readAsBytes();
    return zipBytes([
      for (final file in original.files)
        file.name == entry ? ArchiveFile.bytes(entry, replacementBytes) : file
    ]);
  }

  static Future<void> extractAars(Iterable<String> aars) async {
    for (final aar in aars) {
      await unzip(aar, _fs.extractedAarDir(aar));
    }
  }

  /// Classpath string separator.
  static String get cpSeparator => Platform.isWindows ? ';' : ':';

  static Future<String> javaHomeDir() async {
    final javaHomeEnv = Platform.environment['JAVA_HOME'];
    if (javaHomeEnv != null) {
      return javaHomeEnv;
    }

    final process = await Process.run(
        Platform.isWindows ? 'where' : 'which', ['java'],
        runInShell: true);
    var exe = process.stdout.toString().trim();
    if (LineSplitter.split(exe).length > 1) {
      exe = LineSplitter.split(exe).first;
    }

    try {
      exe = await exe.asFile().resolveSymbolicLinks();
    } catch (_) {}
    return p.dirname(p.dirname(exe));
  }

  static String javaExe([bool getJavac = false]) {
    final javaHome = Platform.environment['JAVA_HOME'];
    if (javaHome != null) {
      return p.join(javaHome, 'bin', getJavac ? 'javac' : 'java');
    }
    return getJavac ? 'javac' : 'java';
  }
}
