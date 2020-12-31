import 'dart:io';

import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/commands/build_command/model/ant_args.dart';
import 'package:rush_cli/commands/build_command/model/designer_component.dart';

import 'package:rush_cli/mixins/app_data_dir_mixin.dart';
import 'package:rush_cli/mixins/copy_mixin.dart';
import 'package:rush_cli/mixins/get_rush_yaml.dart';
import 'package:yaml/yaml.dart';

class BuildCommand with AppDataMixin, CopyMixin {
  final String _currentDir;
  final String _extType;

  BuildCommand(this._currentDir, this._extType);

  /// Builds the extension in the current directory
  Future<void> run() async {
    final rushYml = GetRushYaml.data(_currentDir);
    final dataDir = AppDataMixin.dataStorageDir();
    final pathToAntEx = p.join(dataDir, 'tools', 'apache-ant', 'bin', 'ant');

    var extBox;
    if (await Hive.boxExists(rushYml['name'])) {
      extBox = await Hive.box(rushYml['name']);
    } else {
      extBox = await Hive.openBox(rushYml['name']);
      await extBox.putAll({
        'version': 1,
        'lastMod': DateTime.now().toString(),
        'desAnn': '',
        'astAnn': '',
        'icon': '',
      });
    }

    await _createSrcMirror(dataDir, rushYml, extBox);

    final args = AntArgs(dataDir, _currentDir, _extType).toList();

    // Run the Ant executable
    final process = Process.run(pathToAntEx, args, runInShell: true)
        .asStream()
        .asBroadcastStream();
    process.listen((data) {
      stdout.writeln(data.stdout);
    }, onError: (error) {
      stderr.writeln(error);
    });
  }

  /// Creates exact copy of the extension src directory in the Rush Data Dir.
  /// This is done to add the annotations eliminated by rush.yaml to the Java
  /// source file of the extensions.
  Future<void> _createSrcMirror(
      String dataDirPath, YamlMap rushYml, Box box) async {
    final workspace = p.join(dataDirPath, 'workspaces', _extType);

    // Copy src dir
    final extSrcDir = Directory(p.join(_currentDir, 'src'));
    final mirrorDir = Directory(p.join(workspace, 'temp'));
    mirrorDir.createSync(recursive: true);
    copyDir(extSrcDir, mirrorDir);

    final boxLastMod = box.get('lastMod');
    final curLastMod =
        GetRushYaml.file(_currentDir).lastModifiedSync().toString();

    // Check if the rush.yaml file was modified. If it was, then
    // re-create the required annotations.
    if (curLastMod != boxLastMod) {
      await box.put('lastMod', curLastMod);

      final icon = rushYml['assets']['icon'];

      // Copy extension icon
      if (icon != null && !_isImgUrl(icon)) {
        final destDirPath =
            p.joinAll([workspace, 'temp', ..._extType.split('.'), 'aiwebres']);
        Directory(destDirPath).createSync(recursive: true);

        File(p.join(_currentDir, 'assets', icon))
            .copySync(p.join(destDirPath, icon));
      } else if (icon == null) {
        final dest = p.joinAll([
          workspace,
          'temp',
          ..._extType.split('.'),
          'aiwebres',
          'icon.png'
        ]);

        File(p.join(dataDirPath, 'icon.png')).copySync(dest);
      }

      // Additional annotations that needs to be added to the src box
      if (rushYml['assets']['other'] != null) {
        await box.put('astAnn',
            _getUsesAssets(workspace, icon, rushYml['assets']['other']));
      }
      await box.put('desAnn', _getDesignComp(rushYml, icon, box));
    }

    // Read the actual ext src file.
    //? FIXME
      // This assumes that there is only one extension file in the src tree.
      // Meaning that extension with more than one components won't be possible.
    final extFile = File(p.joinAll(
        [extSrcDir.path, ..._extType.split('.'), '${rushYml['name']}.java']));
    final ext = extFile.readAsLinesSync();

    // Regex to match "@SimpleObject(external=true)"
    final simpleObjPattern =
        RegExp(r'@SimpleObject\s?\(\s?external\s?=\s?true\)');

    final index = ext.indexWhere((line) => line.contains(simpleObjPattern));

    // Replace simpleObjPattern in extFile with designAnn + assetAnn + simpleObjAnn
    final replacement = ext[index].replaceAll(
        simpleObjPattern,
        box.get('desAnn') +
            '\n' +
            box.get('astAnn') +
            '\n@SimpleObject(external=true)');

    ext.removeAt(index);
    ext.insert(index, replacement);

    // Write to the duplicate ext src file.
    File(p.joinAll([
      mirrorDir.path,
      ..._extType.split('.'),
      '${rushYml['name']}.java'
    ])).writeAsStringSync(ext.join('\n'));
  }

  /// Generates the @UsesAssets annotation.
  String _getUsesAssets(String workspace, String icon, List assets) {
    final assetDir = Directory(p.join(_currentDir, 'assets'));
    final assetDest = Directory(
        p.joinAll([workspace, 'temp', ..._extType.split('.'), 'assets']));
    assetDest.createSync(recursive: true);

    copyDir(assetDir, assetDest, leave: [File(icon)]);

    var usesAssets = '@UsesAssets(fileNames = ';
    for (final asset in assets) {
      if (assets.last == asset) {
        usesAssets += '"$asset")';
      } else {
        usesAssets += '"$asset", ';
      }
    }
    return usesAssets;
  }

  /// Generates the @DesignerComponent annotation.
  String _getDesignComp(dynamic rushYml, String icon, Box box) {
    return DesignerComponent(
      category: 'ComponentCategory.EXTENSION',
      desc: rushYml['description'],
      helpUrl: rushYml['homepage'],
      iconName: _isImgUrl(icon) ? '' : 'aiwebres' + icon,
      // license: rushYml['license'],
      minSdk: int.tryParse(rushYml['minSdk'] ?? '7'),
      nonVisible:
          true, //? Until the release of visible ext, this will be hard coded
      version: rushYml['version']['number'] == 'auto'
          ? _getVersion(box)
          : rushYml['version']['number'],
      versionName: rushYml['version']['name'],
    ).toString();
  }

  /// Checks whether the [input] is a URL to image. Particularly used for checking if the extension's icon is an URL.
  bool _isImgUrl(String input) {
    final regex = RegExp(
        r'https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()!@:%_\+.~#?&\/\/=]*)\.(png|jpg|jpeg|svg|gif)',
        dotAll: true);
    return regex.hasMatch(input);
  }

  int _getVersion(Box box) {
    final version = box.get('version') + 1;
    box.put('version', version);
    return version;
  }
}
