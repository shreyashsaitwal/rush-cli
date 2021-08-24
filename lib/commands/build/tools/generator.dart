import 'dart:io' show Directory, File, exit;

import 'package:path/path.dart' as p;
import 'package:rush_cli/commands/build/helpers/build_utils.dart';
import 'package:rush_cli/commands/build/models/rush_lock/rush_lock.dart';
import 'package:rush_cli/commands/build/models/rush_yaml/rush_yaml.dart';
import 'package:rush_cli/version.dart';
import 'package:rush_prompt/rush_prompt.dart';

class Generator {
  final String _cd;
  final String _dataDir;
  final RushYaml _rushYaml;

  Generator(this._cd, this._dataDir, this._rushYaml);

  /// Generates required extension files.
  Future<void> generate(String org, BuildStep step, RushLock? rushLock) async {
    await Future.wait([
      _generateInfoFiles(org),
      _copyAssets(org, step),
      _copyLicense(org),
      _copyRequiredClasses(org, step, rushLock),
    ]);
  }

  /// Generates the components info, build, and the properties file.
  Future<void> _generateInfoFiles(String org) async {
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

  /// Copies extension's assets to the raw directory.
  Future<void> _copyAssets(String org, BuildStep step) async {
    final assets = _rushYaml.assets.other ?? [];

    if (assets.isNotEmpty) {
      final assetsDir = p.join(_cd, 'assets');
      final assetsDestDirX = Directory(
          p.join(_dataDir, 'workspaces', org, 'raw', 'x', org, 'assets'));
      await assetsDestDirX.create(recursive: true);

      for (final el in assets) {
        final asset = File(p.join(assetsDir, el));

        if (asset.existsSync()) {
          await asset.copy(p.join(assetsDestDirX.path, el));
        } else {
          step.log(LogType.warn, 'Unable to find asset "${p.basename(el)}"; skipped.');
        }
      }
    }

    // Pattern to match URL
    final urlPattern = RegExp(
        r'https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()!@:%_\+.~#?&\/\/=]*)',
        dotAll: true);

    final iconName = _rushYaml.assets.icon;

    if (!urlPattern.hasMatch(iconName) && iconName != '') {
      final icon = File(p.join(_cd, 'assets', iconName));
      final iconDestDir = Directory(
          p.join(_dataDir, 'workspaces', org, 'raw', 'x', org, 'aiwebres'));

      await iconDestDir.create(recursive: true);
      await icon.copy(p.join(iconDestDir.path, iconName));
    }
  }

  /// Unjars extension dependencies into the classes dir.
  Future<void> _copyRequiredClasses(
      String org, BuildStep step, RushLock? rushLock) async {
    final implDeps =
        BuildUtils.getDepJarPaths(_cd, _rushYaml, DepScope.implement, rushLock);

    final artDir = Directory(p.join(_dataDir, 'workspaces', org, 'art'))
      ..createSync(recursive: true);

    if (implDeps.isNotEmpty) {
      final desugarStore =
          p.join(_dataDir, 'workspaces', org, 'files', 'desugar');
      final isArtDirEmpty = artDir.listSync().isEmpty;

      for (final el in implDeps) {
        final File dep;

        if (_rushYaml.build?.desugar?.desugar_deps ?? false) {
          dep = File(p.join(desugarStore, el));
        } else {
          dep = File(p.join(_cd, 'deps', el));
        }

        if (!dep.existsSync()) {
          step
            ..log(LogType.erro,
                'Unable to find required library \'${p.basename(dep.path)}\'')
            ..finishNotOk();
          exit(1);
        }

        final isLibModified = dep.existsSync()
            ? dep.lastModifiedSync().isAfter(artDir.statSync().modified)
            : true;

        if (isLibModified || isArtDirEmpty) {
          BuildUtils.unzip(dep.path, artDir.path);
        }
      }
    }

    final kotlinEnabled = _rushYaml.build?.kotlin?.enable ?? false;
    // If Kotlin is enabled, unjar Kotlin std. lib as well. This step won't be
    //needed once MIT merges the Kotlin support PR [#2323].
    if (kotlinEnabled) {
      final ktStdLib =
          File(p.join(_dataDir, 'dev-deps', 'kotlin', 'kotlin-stdlib.jar'));
      BuildUtils.unzip(ktStdLib.path, artDir.path);
    }

    final classesDir =
        Directory(p.join(_dataDir, 'workspaces', org, 'classes'));

    classesDir.listSync(recursive: true).whereType<File>().forEach((el) {
      final newPath =
          p.join(artDir.path, p.relative(el.path, from: classesDir.path));
      Directory(p.dirname(newPath)).createSync(recursive: true);
      el.copySync(newPath);
    });
  }

  /// Copies LICENSE file if there's any.
  Future<void> _copyLicense(String org) async {
    // Pattern to match URL
    final urlPattern = RegExp(
        r'https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()!@:%_\+.~#?&\/\/=]*)',
        dotAll: true);

    final File license;
    if (_rushYaml.license != null && !urlPattern.hasMatch(_rushYaml.license!)) {
      license = File(p.join(_cd, _rushYaml.license));
    } else {
      return;
    }

    final dest = Directory(
        p.join(_dataDir, 'workspaces', org, 'raw', 'x', org, 'aiwebres'));
    await dest.create(recursive: true);

    if (license.existsSync()) {
      await license.copy(p.join(dest.path, 'LICENSE'));
    }
  }
}
