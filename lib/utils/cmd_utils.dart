import 'dart:io' show Directory, File, FileSystemEntity, Platform;

import 'package:path/path.dart' as p;

class CmdUtils {
  // Returns the package name in com.example form
  static String getPackage(String srcDirPath, {String? extName}) {
    final mainSrcFile = () {
      if (extName != null) {
        return Directory(srcDirPath)
            .listSync(recursive: true)
            .whereType<File>()
            .singleWhere(
                (file) => p.basenameWithoutExtension(file.path) == extName);
      } else {
        return Directory(srcDirPath)
            .listSync(recursive: true)
            .whereType<File>()
            .firstWhere((el) =>
                p.extension(el.path) == '.java' ||
                p.extension(el.path) == '.kt');
      }
    }();

    final path = p.relative(mainSrcFile.path, from: srcDirPath);

    final org = path
        .split(p.separator)
        .join('.')
        .split('.' + p.basename(mainSrcFile.path))
        .first;

    return org;
  }

  /// Returns a ";" or ":" separated string of dependencies.
  static String classpathString(List<FileSystemEntity> locations,
      {List<String> exclude = const []}) {
    final jarClassPattern = RegExp(r'^.(jar|class)$');
    final jars = <String>[];

    for (final el in locations) {
      if (el is Directory) {
        final paths = el
            .listSync(recursive: true)
            .whereType<File>()
            .where((el) =>
                !exclude.contains(p.basename(el.path)) &&
                jarClassPattern.hasMatch(p.extension(el.path)))
            .map((el) => el.path)
            .toList();
        jars.addAll(paths);
      } else if (el is File) {
        if (!exclude.contains(p.basename(el.path)) &&
            jarClassPattern.hasMatch(p.extension(el.path))) {
          jars.add(el.path);
        }
      }
    }

    return jars.join(cpSeparator());
  }

  static String cpSeparator() => Platform.isWindows ? ';' : ':';

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

  /// Creates a file in [path] and writes [content] inside it.
  static void writeFile(String path, String content) {
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }
}
