import 'dart:io' show Directory, File, FileSystemEntity, Platform;
import 'package:path/path.dart' as p;

class Helper {
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

  /// Returns a ";" or ":" separated string of dependencies.
  static String generateClasspath(List<FileSystemEntity> entities,
      {List<String> exclude = const [''], Directory? classesDir}) {
    final jars = [];

    entities.forEach((entity) {
      if (entity is Directory) {
        entity
            .listSync(recursive: true)
            .whereType<File>()
            .where((el) =>
                p.extension(el.path) == '.jar' &&
                !exclude.contains(p.basename(el.path)))
            .forEach((el) {
          jars.add(p.relative(el.path));
        });
      } else if (entity is File) {
        jars.add(p.relative(entity.path));
      }
    });

    if (classesDir != null) {
      jars.add(classesDir.path);
    }

    return jars.join(_getSeparator());
  }

  static String _getSeparator() {
    if (Platform.isWindows) {
      return ';';
    }
    return ':';
  }
}
