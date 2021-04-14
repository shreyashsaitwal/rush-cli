import 'dart:io' show Directory, File, FileSystemEntity, Platform;
import 'package:path/path.dart' as p;

class Helper {
  static List<String> getSourceFiles(Directory srcDir) {
    final files = <String>[];

    for (final entity in srcDir.listSync(recursive: true)) {
      if (entity is File && p.extension(entity.path) == '.java') {
        files.add(entity.path);
      }
    }

    return files;
  }

  static String generateClasspath(List<FileSystemEntity> entities,
      {List<String> exclude = const ['']}) {
    final jars = [];

    entities.forEach((entity) {
      if (entity is Directory && !exclude.contains(p.basename(entity.path))) {
        for (final subEnt in entity.listSync(recursive: true)) {
          if (subEnt is File && p.extension(subEnt.path) == '.jar' &&
              !exclude.contains(p.basename(entity.path))) {
            jars.add(subEnt.path);
          }
        }
      } else if (!exclude.contains(p.basename(entity.path))) {
        jars.add(entity.path);
      }
    });

    return jars.join(_getSeparator());
  }

  static String _getSeparator() {
    if (Platform.isWindows) {
      return ';';
    }
    return ':';
  }
}
