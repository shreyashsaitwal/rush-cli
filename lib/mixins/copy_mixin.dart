import 'package:dart_console/dart_console.dart';
import 'package:path/path.dart' as p;
import 'package:rush_prompt/rush_prompt.dart';
import 'dart:io' show Directory, File, FileSystemEntity;

mixin CopyMixin {
  /// Copies the contents of [source] dir to the [dest] dir leaving the optional
  /// files/dirs listed in the [leave].
  void copyDir(Directory source, Directory dest) {
    var files = source.listSync(recursive: true);
    files.forEach((entity) async {
      if (entity is File) {
        await entity.copySync(p.join(dest.path, p.basename(entity.path)));
      } else if (entity is Directory) {
        var newDest = Directory(p.join(dest.path, p.basename(entity.path)));
        copyDir(entity, newDest);
      }
    });
  }
}
