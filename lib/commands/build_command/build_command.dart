import 'dart:io';

import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/commands/build_command/model/ant_args.dart';

import 'package:rush_cli/mixins/app_data_dir_mixin.dart';
import 'package:rush_cli/mixins/copy_mixin.dart';
import 'package:rush_cli/mixins/get_rush_yaml.dart';
import 'package:rush_prompt/rush_prompt.dart';

class BuildCommand with AppDataMixin, CopyMixin {
  final String _currentDir;
  final String _extType;
  final bool _isProd;

  BuildCommand(this._currentDir, this._extType, this._isProd);

  /// Builds the extension in the current directory
  Future<void> run() async {
    final rushYml = GetRushYaml.data(_currentDir);
    final dataDir = AppDataMixin.dataStorageDir();
    final pathToAntEx = p.join(dataDir, 'tools', 'apache-ant', 'bin', 'ant');

    final manifestFile = File(p.join(_currentDir, 'AndroidManifest.xml'));
    if (!manifestFile.existsSync()) {
      ThrowError(message: 'ERR : Unable to find AndroidManifest.xml file in this project.');
    }

    var ymlLastMod = GetRushYaml.file(_currentDir).lastModifiedSync();
    var manifestLastMod = manifestFile.lastModifiedSync();

    var extBox = await Hive.openBox(rushYml['name']);
    if (!extBox.containsKey('version')) {
      await extBox.putAll({
        'version': 1,
      });
    } else if (!extBox.containsKey('rushYmlMod')) {
      await extBox.putAll({
        'rushYmlMod': ymlLastMod,
      });
    } else if (!extBox.containsKey('manifestMod')) {
      await extBox.putAll({
        'manifestMod': manifestLastMod,
      });
    }

    if (ymlLastMod.isAfter(extBox.get('rushYmlMod')) || manifestLastMod.isAfter(extBox.get('manifestMod'))) {
      _cleanBuildDir(dataDir);
    }

    // Increment version number if this is a production build
    if (_isProd) {
      var version = extBox.get('version') + 1;
      await extBox.put('version', version);
    }

    final args =
        AntArgs(dataDir, _currentDir, _extType, extBox.get('version').toString(), rushYml['name'])
            .toList();

    // Run the Ant executable
    Process.run(pathToAntEx, args, runInShell: true)
        .asStream()
        // .asBroadcastStream()
        .listen((data) {
      stdout.writeln(data.stdout);
    }, onError: (error) {
      stderr.writeln(error);
    }, onDone: () {
      // TODO
    });
  }

  void _cleanBuildDir(String dataDir) {
    var buildDir = Directory(p.join(dataDir, 'workspaces', _extType));
    try {
      buildDir.deleteSync(recursive: true);
    } catch (e) {
      ThrowError(message: 'ERR : Something went wrong while invalidating build caches.');
    }
  }
}
