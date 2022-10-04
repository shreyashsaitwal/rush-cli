import 'dart:io' show File, Platform;

import 'package:archive/archive.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;

import 'package:rush_cli/src/config/config.dart';
import 'package:rush_cli/src/services/file_service.dart';
import 'package:rush_cli/src/services/logger.dart';
import 'package:rush_cli/src/utils/file_extension.dart';

class BuildUtils {
  static final _fs = GetIt.I<FileService>();
  static final _lgr = GetIt.I<Logger>();

  static void unzip(String zipFilePath, String outputDirPath) {
    final archive =
        ZipDecoder().decodeBytes(File(zipFilePath).readAsBytesSync());
    for (final el in archive.files) {
      if (el.isFile) {
        final bytes = el.content as List<int>;
        try {
          final file = p.join(outputDirPath, el.name).asFile(true);
          file.writeAsBytesSync(bytes);
        } catch (e) {
          _lgr.parseAndLog('error: ' + e.toString());
          rethrow;
        }
      }
    }
  }

  static void extractAars(Iterable<String> aars) {
    for (final aar in aars) {
      final String dist;
      
      // Extract local AARs in .rush/build/extracted-aars dir, whereas remote AARs
      // in their original location under {aar_basename} dir.
      if (p.isWithin(_fs.localDepsDir.path, aar)) {
        dist = p.join(_fs.buildAarsDir.path, p.basenameWithoutExtension(aar));
      } else {
        dist = p.join(p.dirname(aar), p.basenameWithoutExtension(aar));
      }
      BuildUtils.unzip(aar, dist);
    }
  }

  /// Classpath string separator.
  static String get cpSeparator => Platform.isWindows ? ';' : ':';

  /// Copies extension's assets to the raw directory.
  static void copyAssets(Config config) {
    final assets = config.assets;
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
        throw Exception('Asset $el does not exist');
      }
    }
  }

  /// Copies LICENSE file if there's any.
  static void copyLicense(Config config) {
    // Pattern to match URL
    final urlPattern = RegExp(
        r'https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()!@:%_\+.~#?&\/\/=]*)',
        dotAll: true);

    final File license;
    if (config.license != '' && !urlPattern.hasMatch(config.license)) {
      license = p.join(_fs.cwd, config.license).asFile();
    } else {
      return;
    }

    final dest = p.join(_fs.buildRawDir.path, 'aiwebres').asDir(true);
    if (license.existsSync()) {
      license.copySync(p.join(dest.path, 'LICENSE'));
    }
  }
}
