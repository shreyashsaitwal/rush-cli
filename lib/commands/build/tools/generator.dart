import 'dart:io' show Directory, File, exit;

import 'package:path/path.dart' as p;
import 'package:rush_cli/commands/build/utils/build_utils.dart';
import 'package:rush_cli/commands/build/models/rush_lock/rush_lock.dart';
import 'package:rush_cli/commands/build/models/rush_yaml/rush_yaml.dart';
import 'package:rush_cli/utils/cmd_utils.dart';
import 'package:rush_cli/services/file_service.dart';
import 'package:rush_cli/version.dart';
import 'package:rush_prompt/rush_prompt.dart';

class Generator {
  final FileService _fs;
  final RushYaml _rushYaml;

  Generator(this._fs, this._rushYaml);

  /// Generates required extension files.
  Future<void> generate(BuildStep step, RushLock? rushLock) async {
    await Future.wait([
      _generateInfoFiles(),
      _copyAssets(step),
      _copyLicense(),
      _copyRequiredClasses(step, rushLock),
    ]);
  }

  /// Generates the components info, build, and the properties file.
  Future<void> _generateInfoFiles() async {
    final filesDirPath = p.join(_fs.buildDir, 'files');
    final rawDir = Directory(p.join(_fs.buildDir, 'raw'));
    await rawDir.create(recursive: true);

    // Copy the components.json file to the raw dir.
    File(p.join(filesDirPath, 'components.json'))
        .copy(p.join(rawDir.path, 'components.json'));

    // Copy the component_build_infos.json file to the raw dir.
    final rawFilesDir = Directory(p.join(rawDir.path, 'files'));
    await rawFilesDir.create(recursive: true);
    await File(p.join(filesDirPath, 'component_build_infos.json'))
        .copy(p.join(rawFilesDir.path, 'component_build_infos.json'));

    // Write the extension.properties file
    await File(p.join(rawDir.path, 'extension.properties')).writeAsString('''
type=external
rush-version=$rushVersion
''');
  }

  /// Copies extension's assets to the raw directory.
  Future<void> _copyAssets(BuildStep step) async {
    final assets = _rushYaml.assets ?? [];

    if (assets.isNotEmpty) {
      final assetsDir = p.join(_fs.cwd, 'assets');
      final assetsDestDir = Directory(p.join(_fs.buildDir, 'raw', 'assets'));
      await assetsDestDir.create(recursive: true);

      for (final el in assets) {
        final asset = File(p.join(assetsDir, el));

        if (await asset.exists()) {
          await asset.copy(p.join(assetsDestDir.path, el));
        } else {
          step.log(LogType.warn,
              'Unable to find asset "${p.basename(el)}"; skipped.');
        }
      }
    }

    // If the icons are not URLs, the annotation processor copies them to the
    // files/aiwebres dir. Check if that dir exists, if it does, copy the icon
    // files from there.
    final aiwebres = Directory(p.join(_fs.buildDir, 'files', 'aiwebres'));
    if (await aiwebres.exists()) {
      final dest = Directory(p.join(_fs.buildDir, 'raw', 'aiwebres'));
      await dest.create(recursive: true);

      CmdUtils.copyDir(aiwebres, dest);
      await aiwebres.delete(recursive: true);
    }
  }

  /// Unjars extension dependencies into the classes dir.
  Future<void> _copyRequiredClasses(BuildStep step, RushLock? rushLock) async {
    final implDeps = BuildUtils.getDepJarPaths(
        _fs.cwd, _rushYaml, DepScope.implement, rushLock);

    final artDir = Directory(p.join(_fs.buildDir, 'art'))
      ..createSync(recursive: true);

    if (implDeps.isNotEmpty) {
      final desugarStore = p.join(_fs.buildDir, 'files', 'desugar');
      final isArtDirEmpty = artDir.listSync().isEmpty;

      for (final el in implDeps) {
        final File dep;

        if (_rushYaml.desugar?.deps ?? false) {
          dep = File(p.join(desugarStore, el));
        } else {
          dep = File(p.join(_fs.cwd, 'deps', el));
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

    final kotlinEnabled = _rushYaml.kotlin?.enable ?? false;
    // If Kotlin is enabled, unjar Kotlin std. lib as well. This step won't be
    //needed once MIT merges the Kotlin support PR [#2323].
    if (kotlinEnabled) {
      final ktStdLib =
          File(p.join(_fs.devDepsDir, 'kotlin', 'kotlin-stdlib.jar'));
      BuildUtils.unzip(ktStdLib.path, artDir.path);
    }

    final classesDir = Directory(p.join(_fs.buildDir, 'classes'));

    classesDir.listSync(recursive: true).whereType<File>().forEach((el) {
      final newPath =
          p.join(artDir.path, p.relative(el.path, from: classesDir.path));
      Directory(p.dirname(newPath)).createSync(recursive: true);
      el.copySync(newPath);
    });
  }

  /// Copies LICENSE file if there's any.
  Future<void> _copyLicense() async {
    // Pattern to match URL
    final urlPattern = RegExp(
        r'https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()!@:%_\+.~#?&\/\/=]*)',
        dotAll: true);

    final File license;
    if (_rushYaml.license != null && !urlPattern.hasMatch(_rushYaml.license!)) {
      license = File(p.join(_fs.cwd, _rushYaml.license));
    } else {
      return;
    }

    final dest = Directory(p.join(_fs.buildDir, 'raw', 'aiwebres'));
    await dest.create(recursive: true);

    if (license.existsSync()) {
      await license.copy(p.join(dest.path, 'LICENSE'));
    }
  }
}
