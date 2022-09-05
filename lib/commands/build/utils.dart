import 'dart:io' show Directory, File, Platform;

import 'package:archive/archive.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/utils/file_extension.dart';

import '../../config/rush_yaml.dart';
import '../../services/file_service.dart';

class BuildUtils {
  static final _fs = GetIt.I<FileService>();

  static void unzip(String zipFilePath, String outputDirPath) {
    final archive =
        ZipDecoder().decodeBytes(File(zipFilePath).readAsBytesSync());
    for (final el in archive.files) {
      if (el.isFile) {
        final bytes = el.content as List<int>;
        try {
          final file = p.join(outputDirPath, el.name).asFile(true);
          file.writeAsBytesSync(bytes);
        } catch (e, s) {
          print(e);
          print(s);
          rethrow;
        }
      }
    }
  }

  /// Classpath string separator.
  static String get cpSeparator => Platform.isWindows ? ';' : ':';

  /// Copies extension's assets to the raw directory.
  static void copyAssets(RushYaml rushYaml) {
    final assets = rushYaml.assets;
    if (assets.isEmpty) {
      return;
    }

    final assetsDir = p.join(_fs.cwd, 'assets');
    final assetsDestDir = p.join(_fs.buildRawDir.path, 'assets').asDir()
      ..createSync(recursive: true);

    for (final el in assets) {
      final asset = p.join(assetsDir, el).asFile();
      if (asset.existsSync()) {
        asset.copySync(p.join(assetsDestDir.path, el));
      } else {
        // TODO: Log
      }
    }
  }

  /// Copies LICENSE file if there's any.
  static void copyLicense(RushYaml rushYaml) {
    // Pattern to match URL
    final urlPattern = RegExp(
        r'https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()!@:%_\+.~#?&\/\/=]*)',
        dotAll: true);

    final File license;
    if (rushYaml.license != '' && !urlPattern.hasMatch(rushYaml.license)) {
      license = p.join(_fs.cwd, rushYaml.license).asFile();
    } else {
      return;
    }

    final dest = Directory(p.join(_fs.buildRawDir.path, 'aiwebres'));
    dest.createSync(recursive: true);

    if (license.existsSync()) {
      license.copySync(p.join(dest.path, 'LICENSE'));
    }
  }
}
