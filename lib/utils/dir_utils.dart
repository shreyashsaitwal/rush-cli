import 'dart:io' show Directory, File, Platform, exit;

import 'package:path/path.dart' as p;
import 'package:rush_prompt/rush_prompt.dart';

class DirUtils {
  static String? dataDir() {
    final os = Platform.operatingSystem;
    final String appDataDir;

    if (Platform.environment.containsKey('RUSH_DATA_DIR')) {
      appDataDir = Platform.environment['RUSH_DATA_DIR']!;
    } else {
      switch (os) {
        // TODO: Data dir should be named `.rush` and should be created in the
        // user's home directory in all OSs.
        case 'windows':
          appDataDir = p.join(Platform.environment['UserProfile']!, 'AppData',
              'Roaming', 'rush');
          break;
        case 'macos':
          appDataDir = p.join(Platform.environment['HOME']!, 'Library',
              'Application Support', 'rush');
          break;
        default:
          appDataDir = p.join(Platform.environment['HOME']!, 'rush');
          break;
      }
    }

    final dir = Directory(appDataDir);
    if (!dir.existsSync() || dir.listSync().isEmpty) {
      Logger.log(LogType.erro,
          'Rush data directory $appDataDir doesn\'t exists or is empty');
      exit(1);
    }

    return appDataDir;
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
