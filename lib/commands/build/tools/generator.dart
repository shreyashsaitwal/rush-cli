import 'dart:io' show Directory, File;

import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/services/file_service.dart';
import 'package:rush_cli/utils/utils.dart';
import 'package:rush_cli/version.dart';

import '../../../config/rush_yaml.dart';

// TODO: Logging
class Generator {
  static final _fs = GetIt.I<FileService>();

  /// Generates required extension files.
  static Future<void> generate(RushYaml rushYaml) async {
    await Future.wait([
      _generateInfoFiles(),
      _copyAssets(rushYaml),
      _copyLicense(rushYaml),
    ]);
  }

  /// TODO: Make AP generate these file directly in the desired directory.
  static Future<void> _generateInfoFiles() async {
    // Copy the components.json file to the raw dir.
    await File(p.join(_fs.buildFilesDir.path, 'components.json'))
        .copy(p.join(_fs.buildRawDir.path, 'components.json'));

    // Copy the component_build_infos.json file to the raw dir.
    final rawFilesDir = Directory(p.join(_fs.buildRawDir.path, 'files'));
    await rawFilesDir.create(recursive: true);
    await File(p.join(_fs.buildFilesDir.path, 'component_build_infos.json'))
        .copy(p.join(rawFilesDir.path, 'component_build_infos.json'));

    // Write the extension.properties file
    await File(p.join(_fs.buildRawDir.path, 'extension.properties'))
        .writeAsString('type=external\nrush-version=$rushVersion');
  }

  /// Copies extension's assets to the raw directory.
  static Future<void> _copyAssets(RushYaml rushYaml) async {
    final assets = rushYaml.assets;

    if (assets.isNotEmpty) {
      final assetsDir = p.join(_fs.cwd, 'assets');
      final assetsDestDir = Directory(p.join(_fs.buildRawDir.path, 'assets'));
      await assetsDestDir.create(recursive: true);

      for (final el in assets) {
        final asset = File(p.join(assetsDir, el));

        if (await asset.exists()) {
          await asset.copy(p.join(assetsDestDir.path, el));
        } else {
          // TODO: Log
        }
      }
    }

    // If the icons are not URLs, the annotation processor copies them to the
    // files/aiwebres dir. Check if that dir exists, if it does, copy the icon
    // files from there.
    final aiwebres = Directory(p.join(_fs.buildFilesDir.path, 'aiwebres'));
    if (await aiwebres.exists()) {
      final dest = Directory(p.join(_fs.buildRawDir.path, 'aiwebres'));
      await dest.create(recursive: true);
      await Utils.copyDir(aiwebres, dest);
      await aiwebres.delete(recursive: true);
    }
  }

  /// Copies LICENSE file if there's any.
  static Future<void> _copyLicense(RushYaml rushYaml) async {
    // Pattern to match URL
    final urlPattern = RegExp(
        r'https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()!@:%_\+.~#?&\/\/=]*)',
        dotAll: true);

    final File license;
    if (rushYaml.license != '' && !urlPattern.hasMatch(rushYaml.license)) {
      license = File(p.join(_fs.cwd, rushYaml.license));
    } else {
      return;
    }

    final dest = Directory(p.join(_fs.buildRawDir.path, 'aiwebres'));
    await dest.create(recursive: true);

    if (await license.exists()) {
      await license.copy(p.join(dest.path, 'LICENSE'));
    }
  }
}
