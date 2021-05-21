import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:rush_cli/helpers/utils.dart';
import 'package:rush_cli/version.dart';
import 'package:yaml/yaml.dart';

class Generator {
  final String _cd;
  final String _dataDir;

  Generator(this._cd, this._dataDir);

  /// Generates required extension files.
  void generate(String org) {
    final rushYml = File(p.join(_cd, 'rush.yml'));
    final rushYaml = File(p.join(_cd, 'rush.yaml'));

    final YamlMap yml;
    if (rushYml.existsSync()) {
      yml = loadYaml(rushYml.readAsStringSync());
    } else {
      // No need to check if this file exist. If it didn't
      // build command would have already thrown an error.
      yml = loadYaml(rushYaml.readAsStringSync());
    }

    _generateRawFiles(org);
    _copyAssets(yml, org);
    _copyLicense(org);
    _copyDeps(yml, org);
  }

  /// Generates the components info and build files and the properties file.
  void _generateRawFiles(String org) {
    final rawDirX =
        Directory(p.join(_dataDir, 'workspaces', org, 'raw', 'x', org))
          ..createSync(recursive: true);

    final filesDirPath = p.join(_dataDir, 'workspaces', org, 'files');

    // Copy the components.json file to the raw dir.
    final simpleCompJson = File(p.join(filesDirPath, 'components.json'));
    simpleCompJson.copySync(p.join(rawDirX.path, 'components.json'));

    // Copy the component_build_infos.json file to the raw dir.
    final buildInfoJson =
        File(p.join(filesDirPath, 'component_build_infos.json'));

    final rawFilesDir = Directory(p.join(rawDirX.path, 'files'))
      ..createSync(recursive: true);

    buildInfoJson
        .copySync(p.join(rawFilesDir.path, 'component_build_infos.json'));

    // Write the extension.properties file
    File(p.join(rawDirX.path, 'extension.properties')).writeAsStringSync('''
type=external
rush-version=$rushVersion
''');
  }

  /// Copies extension's assets to the raw dircetory.
  void _copyAssets(YamlMap rushYml, String org) {
    final assets = rushYml['assets']['other'] ?? [];

    if (assets.isNotEmpty) {
      final assetsDir = p.join(_cd, 'assets');
      final assetsDestDirX = Directory(
          p.join(_dataDir, 'workspaces', org, 'raw', 'x', org, 'assets'))
        ..createSync(recursive: true);

      assets.forEach((el) {
        final asset = File(p.join(assetsDir, el));
        asset.copySync(p.join(assetsDestDirX.path, el));
      });
    }

    // Pattern to match URL
    final urlPattern = RegExp(
        r'https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()!@:%_\+.~#?&\/\/=]*)',
        dotAll: true);

    final iconName = rushYml['assets']['icon'] ?? '';

    if (!urlPattern.hasMatch(iconName) && iconName != '') {
      final icon = File(p.join(_cd, 'assets', iconName));
      final iconDestDir = Directory(
          p.join(_dataDir, 'workspaces', org, 'raw', 'x', org, 'aiwebres'))
        ..createSync(recursive: true);

      icon.copySync(p.join(iconDestDir.path, iconName));
    }
  }

  /// Unjars extension dependencies into the classes dir.
  void _copyDeps(YamlMap rushYml, String org) {
    final libs = rushYml['deps'] ?? [];

    final classesDir =
        Directory(p.join(_dataDir, 'workspaces', org, 'classes'))
          ..createSync(recursive: true);

    if (libs.isNotEmpty) {
      final depsDirPath = p.join(_cd, 'deps');

      libs.forEach((el) {
        final lib = p.join(depsDirPath, el);
        Utils.extractJar(lib, classesDir.path);
      });
    }

    final kotlinEnabled = rushYml['kotlin']?['enable'] ?? false;

    // If Kotlin is enabled, unjar Kotlin std. lib as well.
    // This step won't be needed once MIT merges the Kotlin support PR.
    if (kotlinEnabled) {
      final kotlinStdLib =
          File(p.join(_cd, '.rush', 'dev-deps', 'kotlin-stdlib.jar'));

      Utils.extractJar(kotlinStdLib.path, classesDir.path);
    }
  }

  /// Copies LICENSE file if there's any.
  void _copyLicense(String org) {
    final license = File(p.join(_cd, 'LICENSE'));
    final licenseTxt = File(p.join(_cd, 'LICENSE.txt'));

    final dest = Directory(
        p.join(_dataDir, 'workspaces', org, 'raw', 'x', org, 'aiwebres'))
      ..createSync(recursive: true);

    if (license.existsSync()) {
      license.copySync(p.join(dest.path, 'LICENSE'));
    } else if (licenseTxt.existsSync()) {
      licenseTxt.copy(p.join(dest.path, 'LICENSE'));
    }
  }
}
