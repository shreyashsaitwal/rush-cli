import 'dart:io' show Directory, File, FileSystemEntity, Platform;

import 'package:path/path.dart' as p;

class CmdUtils {
  // Returns the package name in com.example form
  static String getPackage(String extName, String srcDirPath) {
    final mainSrcFile = Directory(srcDirPath)
        .listSync(recursive: true)
        .whereType<File>()
        .singleWhere(
            (file) => p.basenameWithoutExtension(file.path) == extName);

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
      {List<FileSystemEntity>? ignore}) {
    var files = source.listSync();

    for (final entity in files) {
      if (ignore != null && ignore.contains(entity)) {
        continue;
      }
      if (entity is File) {
        entity.copySync(p.join(dest.path, p.basename(entity.path)));
      } else if (entity is Directory) {
        var newDest =
            Directory(p.join(dest.path, entity.path.split(p.separator).last));
        newDest.createSync();
        copyDir(entity, newDest);
      }
    }
  }

  /// Returns a ";" or ":" separated string of dependencies.
  static String generateClasspath(List<FileSystemEntity> entities,
      {List<String> exclude = const [''],
      Directory? classesDir,
      bool relative = true}) {
    final jars = <String>[];

    for (final entity in entities) {
      if (entity is Directory) {
        entity
            .listSync(recursive: true)
            .whereType<File>()
            .where((el) =>
                p.extension(el.path) == '.jar' &&
                !exclude.contains(p.basename(el.path)))
            .forEach((el) {
          if (relative) {
            jars.add(p.relative(el.path));
          } else {
            jars.add(el.path);
          }
        });
      } else if (entity is File) {
        if (relative) {
          jars.add(p.relative(entity.path));
        } else {
          jars.add(entity.path);
        }
      }
    }

    if (classesDir != null) {
      jars.add(classesDir.path);
    }

    return jars.join(getSeparator());
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

  static String getSeparator() {
    if (Platform.isWindows) {
      return ';';
    }
    return ':';
  }
}
