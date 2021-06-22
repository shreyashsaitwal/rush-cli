import 'dart:io' show Platform, Directory;

import 'package:path/path.dart' as path;

class RushDataDir {
  static String? dataDir() {
    var os = Platform.operatingSystem;
    late String appDataDir;

    switch (os) {
      case 'windows':
        appDataDir = path.join(
            Platform.environment['UserProfile']!, 'AppData', 'Roaming');
        break;

      case 'macos':
        appDataDir = path.join(
            Platform.environment['HOME']!, 'Library', 'Application Support');
        break;

      case 'linux':
        appDataDir = path.join('home', Platform.environment['HOME']);
        break;

      default:
        break;
    }

    if (Directory(appDataDir).existsSync()) {
      final rushStorage = path.join(appDataDir, 'rush');
      try {
        Directory(rushStorage).createSync(recursive: true);
      } catch (e) {
        print(e); // TODO remove print statement
        return null;
      }
      return rushStorage;
    } else {
      return null;
    }
  }
}
