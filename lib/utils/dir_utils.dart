import 'dart:io' show Directory, File, Platform, exit;

import 'package:path/path.dart' as p;
import 'package:rush_prompt/rush_prompt.dart';

class DirUtils {
  static String? dataDir() {
    final os = Platform.operatingSystem;
    late String appDataDir;

    switch (os) {
      case 'windows':
        appDataDir =
            p.join(Platform.environment['UserProfile']!, 'AppData', 'Roaming');
        break;
      case 'macos':
        appDataDir = p.join(
            Platform.environment['HOME']!, 'Library', 'Application Support');
        break;
      case 'linux':
        appDataDir = p.join('home', Platform.environment['HOME']);
        break;
      default:
        break;
    }

    final dataDir = Directory(p.join(appDataDir, 'rush'));
    if (!dataDir.existsSync()) {
      Logger.log(LogType.erro, 'Rush data directory doesn\'t exists');
      exit(1);
    }
    return dataDir.path;
  }

  /// Copies the contents of [source] dir to the [dest] dir.
  static void copyDir(Directory source, Directory dest,
      {List<String>? ignorePaths}) {
    final files = source.listSync();

    for (final entity in files) {
      if (ignorePaths != null && ignorePaths.contains(entity.path)) {
        continue;
      }
      if (entity is File) {
        entity.copySync(p.join(dest.path, p.basename(entity.path)));
      } else if (entity is Directory && entity.listSync().isNotEmpty) {
        final newDest =
            Directory(p.join(dest.path, entity.path.split(p.separator).last));
        newDest.createSync();
        copyDir(entity, newDest);
      }
    }
  }
}
