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

  /// Copies the contents of [source] dir to the [dest] dir.
  static void copyDir(Directory source, Directory dest,
      {List<String>? ignorePaths}) {
    var files = source.listSync();

    for (final entity in files) {
      if (ignorePaths != null && ignorePaths.contains(entity.path)) {
        continue;
      }
      if (entity is File) {
        entity.copySync(p.join(dest.path, p.basename(entity.path)));
      } else if (entity is Directory && entity.listSync().isNotEmpty) {
        var newDest =
            Directory(p.join(dest.path, entity.path.split(p.separator).last));
        newDest.createSync();
        copyDir(entity, newDest);
      }
    }
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
