import 'dart:io' show Directory, Platform, exit;

import 'package:path/path.dart' as p;
import 'package:rush_prompt/rush_prompt.dart';

class DirUtils {
  static String? dataDir() {
    var os = Platform.operatingSystem;
    final String appDataDir;

    if (Platform.environment.containsKey('RUSH_DATA_DIR')) {
      appDataDir = Platform.environment['RUSH_DATA_DIR']!;
    } else {
      switch (os) {
        case 'windows':
          appDataDir = p.join(
              Platform.environment['UserProfile']!, 'AppData', 'Roaming', 'rush');
          break;

        case 'macos':
          appDataDir = p.join(
              Platform.environment['HOME']!, 'Library', 'Application Support', 'rush');
          break;

        default:
          appDataDir = p.join(Platform.environment['HOME']!, 'rush');
          break;
      }
    }

    if (!Directory(appDataDir).existsSync()) {
      Logger.log(LogType.erro, 'Rush data directory $appDataDir doesn\'t exists');
      exit(1);
    }
    return appDataDir;
  }
}
