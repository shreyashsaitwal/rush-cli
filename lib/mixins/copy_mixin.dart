import 'package:path/path.dart' as path;
import 'package:rush_prompt/rush_prompt.dart';
import 'dart:io' show Directory, File;

mixin CopyMixin {
  /// Copies the contents of [source] dir to the [dest] dir
  void copyDir(Directory source, Directory dest) {
    final entities = source.listSync(recursive: false);

    for (final entity in entities) {
      if (entity is Directory) {
        final dir = Directory(
            path.join(dest.absolute.path, path.basename(entity.path)));
        dir.createSync();
        copyDir(entity, dir);
      } else if (entity is File) {
        entity.copySync(
            path.join(dest.absolute.path, path.basename(entity.path)));
      }
    }
  }

  void copyDirWithProg(Directory source, Directory dest, String title) {
    final progress = ProgressBar(title);
    var progCount = 0;

    final entities = source.listSync(recursive: false);
    progress.totalProgress = entities.length;

    for (final entity in entities) {
      progCount++;
      progress.update(progCount);

      if (entity is Directory) {
        final dir = Directory(
            path.join(dest.absolute.path, path.basename(entity.path)));
        dir.createSync();
        copyDir(entity, dir);
      } else if (entity is File) {
        entity.copySync(
            path.join(dest.absolute.path, path.basename(entity.path)));
      }
    }
  }
}