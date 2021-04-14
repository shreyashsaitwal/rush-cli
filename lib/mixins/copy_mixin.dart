import 'package:path/path.dart' as p;
import 'dart:io' show Directory, File, FileSystemEntity;

mixin CopyMixin {
  /// Copies the contents of [source] dir to the [dest] dir.
  void copyDir(Directory source, Directory dest,
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
            Directory(p.join(dest.path, entity.path.split('\\').last));
        newDest.createSync();
        copyDir(entity, newDest);
      }
    }
  }
}
