import 'dart:io' show Directory, Link, Platform, exit;

import 'package:path/path.dart' as p;
import 'package:rush_cli/helpers/cmd_utils.dart';
import 'package:rush_prompt/rush_prompt.dart';

class DirUtils {
  static String? dataDir() {
    var os = Platform.operatingSystem;
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
}
