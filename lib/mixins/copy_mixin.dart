import 'package:path/path.dart' as p;
import 'dart:io' show Directory, File;

mixin CopyMixin {
  /// Copies the contents of [source] dir to the [dest] dir.
  void copyDir(Directory source, Directory dest) {
    var files = source.listSync();
    files.forEach((entity) async {
      if (entity is File) {
        entity.copySync(p.join(dest.path, p.basename(entity.path)));
      } else if (entity is Directory) {
        var newDest = Directory(p.join(dest.path, entity.path.split('\\').last));
        newDest.createSync();
        copyDir(entity, newDest);
      }
    });
  }
}
