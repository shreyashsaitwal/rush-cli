import 'dart:io' show Directory, File;

import 'package:path/path.dart' as p;

class Utils {
  /// Creates a file in [path] and writes [content] inside it.
  static Future<void> writeFile(String path, String content) async {
    final file = File(path);
    await file.create(recursive: true);
    await file.writeAsString(content);
  }

  /// Copies the contents of [source] dir to the [dest] dir.
  static Future<void> copyDir(
    Directory source,
    Directory dest, {
    List<String>? ignorePaths,
  }) async {
    final files = source.listSync();
    for (final entity in files) {
      if (ignorePaths?.contains(entity.path) ?? false) {
        continue;
      }
      if (entity is File) {
        await entity.copy(p.join(dest.path, p.basename(entity.path)));
      } else if (entity is Directory && entity.listSync().isNotEmpty) {
        final newDest =
            Directory(p.join(dest.path, entity.path.split(p.separator).last));
        await newDest.create();
        await copyDir(entity, newDest);
      }
    }
  }
}
