import 'dart:io' show Directory, File;
import 'package:path/path.dart' as p;

extension FileExtension on String {
  Directory asDir([bool create = false]) {
    final dir = Directory(this);
    if (!dir.existsSync() && create) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  File asFile([bool create = false]) {
    final file = File(this);
    if (!file.existsSync() && create) {
      file.createSync(recursive: true);
    }
    return file;
  }

  Directory parentDir() => p.dirname(this).asDir();
}
