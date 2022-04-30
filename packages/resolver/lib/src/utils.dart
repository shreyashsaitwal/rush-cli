import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

class Utils {
  static get defaultCacheDir => () {
        final Directory dir;
        switch (Platform.operatingSystem) {
          case 'windows':
            dir = Directory(p.join(
                Platform.environment['UserProfile']!, '.m2', 'repository'));
            break;
          default:
            dir = Directory(
                p.join(Platform.environment['HOME']!, '.m2', 'repository'));
            break;
        }

        if (!dir.existsSync()) {
          dir.createSync(recursive: true);
        }

        return dir.path;
      }();

  static File writeFile(
    String path,
    Uint8List content,
  ) {
    try {
      Directory(p.dirname(path)).createSync(recursive: true);
      return File(path)..writeAsBytesSync(content);
    } catch (e) {
      rethrow;
    }
  }
}
