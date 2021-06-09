import 'dart:io' show Directory, File;

import 'package:checked_yaml/checked_yaml.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/commands/build_command/models/rush_yaml.dart';
import 'package:rush_cli/version.dart';
import 'package:rush_prompt/rush_prompt.dart';

import 'build_utils.dart';

class Generator {
  final String _cd;
  final String _dataDir;

  Generator(this._cd, this._dataDir);

  /// Generates required extension files.
  Future<void> generate(String org, BuildStep step) async {
    final rushYaml = checkedYamlDecode(
      await BuildUtils.getRushYaml(_cd).readAsString(),
      (json) => RushYaml.fromJson(json!),
      sourceUrl: Uri.tryParse(
          'https://raw.githubusercontent.com/shreyashsaitwal/rush-cli/main/schema/rush.json'),
    );

    await Future.wait([
      _generateRawFiles(org),
      _copyAssets(rushYaml, org),
      _copyLicense(org),
      _copyDeps(rushYaml, org, step),
    ]);
  }

  /// Generates the components info, build, and the properties file.
  Future<void> _generateRawFiles(String org) async {
    final rawDirX =
        Directory(p.join(_dataDir, 'workspaces', org, 'raw', 'x', org));
    await rawDirX.create(recursive: true);

    final filesDirPath = p.join(_dataDir, 'workspaces', org, 'files');

    // Copy the components.json file to the raw dir.
    final simpleCompJson = File(p.join(filesDirPath, 'components.json'));
    await simpleCompJson.copy(p.join(rawDirX.path, 'components.json'));

    // Copy the component_build_infos.json file to the raw dir.
    final buildInfoJson =
        File(p.join(filesDirPath, 'component_build_infos.json'));

    final rawFilesDir = Directory(p.join(rawDirX.path, 'files'));
    await rawFilesDir.create(recursive: true);

    await buildInfoJson
        .copy(p.join(rawFilesDir.path, 'component_build_infos.json'));

    // Write the extension.properties file
    await File(p.join(rawDirX.path, 'extension.properties')).writeAsString('''
type=external
rush-version=$rushVersion
''');
  }

  /// Copies extension's assets to the raw dircetory.
  Future<void> _copyAssets(RushYaml rushYml, String org) async {
    final assets = rushYml.assets.other ?? [];

    if (assets.isNotEmpty) {
      final assetsDir = p.join(_cd, 'assets');
      final assetsDestDirX = Directory(
          p.join(_dataDir, 'workspaces', org, 'raw', 'x', org, 'assets'));
      await assetsDestDirX.create(recursive: true);

      assets.forEach((el) async {
        final asset = File(p.join(assetsDir, el));
        await asset.copy(p.join(assetsDestDirX.path, el));
      });
    }

    // Pattern to match URL
    final urlPattern = RegExp(
        r'https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()!@:%_\+.~#?&\/\/=]*)',
        dotAll: true);

    final iconName = rushYml.assets.icon;

    if (!urlPattern.hasMatch(iconName) && iconName != '') {
      final icon = File(p.join(_cd, 'assets', iconName));
      final iconDestDir = Directory(
          p.join(_dataDir, 'workspaces', org, 'raw', 'x', org, 'aiwebres'));

      await iconDestDir.create(recursive: true);
      await icon.copy(p.join(iconDestDir.path, iconName));
    }
  }

  /// Unjars extension dependencies into the classes dir.
  Future<void> _copyDeps(RushYaml rushYml, String org, BuildStep step) async {
    final libs = rushYml.deps ?? [];

    final classesDir =
        Directory(p.join(_dataDir, 'workspaces', org, 'classes'));
    await classesDir.create(recursive: true);

    if (libs.isNotEmpty) {
      final depsDirPath = p.join(_cd, 'deps');

      libs.forEach((el) {
        final lib = p.join(depsDirPath, el);
        BuildUtils.extractJar(lib, classesDir.path, step);
      });
    }

    final kotlinEnabled = rushYml.kotlin?.enable ?? false;

    // If Kotlin is enabled, unjar Kotlin std. lib as well.
    // This step won't be needed once MIT merges the Kotlin support PR.
    if (kotlinEnabled) {
      final kotlinStdLib =
          File(p.join(_cd, '.rush', 'dev-deps', 'kotlin-stdlib.jar'));

      BuildUtils.extractJar(kotlinStdLib.path, classesDir.path, step);
    }
  }

  /// Copies LICENSE file if there's any.
  Future<void> _copyLicense(String org) async {
    final license = File(p.join(_cd, 'LICENSE'));
    final licenseTxt = File(p.join(_cd, 'LICENSE.txt'));

    final dest = Directory(
        p.join(_dataDir, 'workspaces', org, 'raw', 'x', org, 'aiwebres'));
    await dest.create(recursive: true);

    if (await license.exists()) {
      await license.copy(p.join(dest.path, 'LICENSE'));
    } else if (await licenseTxt.exists()) {
      await licenseTxt.copy(p.join(dest.path, 'LICENSE'));
    }
  }
}
