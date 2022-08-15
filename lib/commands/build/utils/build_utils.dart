import 'dart:io' show Directory, File, Platform, exit;

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/utils/file_extension.dart';

class BuildUtils {
  static void unzip(String zipFilePath, String outputDirPath) {
    final archive =
        ZipDecoder().decodeBytes(File(zipFilePath).readAsBytesSync());

    for (final el in archive.files) {
      if (el.isFile) {
        final bytes = el.content as List<int>;
        try {
          final file = p.join(outputDirPath, el.name).asFile(true);
          file.writeAsBytesSync(bytes);
        } catch (e, s) {
          print(e);
          print(s);
          rethrow;
        }
      }
    }
  }

  /// Returns a list of paths that represent Java sources files.
  static List<String> getJavaSourceFiles(Directory srcDir) {
    final files = <String>[];
    final srcFiles = srcDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((el) => p.extension(el.path) == '.java')
        .map((el) => el.path);
    files.addAll(srcFiles);
    return files;
  }

  /// Classpath string separator.
  static String get cpSeparator => Platform.isWindows ? ';' : ':';
}
