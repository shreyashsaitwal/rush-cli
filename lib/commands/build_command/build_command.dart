import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:rush_cli/commands/build_command/model/designer_component.dart';

import 'package:rush_cli/mixins/app_data_dir_mixin.dart';
import 'package:rush_cli/mixins/copy_mixin.dart';
import 'package:rush_prompt/rush_prompt.dart';
import 'package:yaml/yaml.dart';

class BuildCommand with AppDataMixin, CopyMixin {
  BuildCommand(this._currentDir, this._extType);

  final String _currentDir;
  final String _extType;

  /// Builds this extension
  void run() {
    if (!Directory(_currentDir).listSync().contains(File('rush.yaml'))) {
      ThrowError(message: 'Unable to find "rush.yaml" in this directory.');
    }

    final dataDir = AppDataMixin.dataStorageDir();
    final pathToAntEx = path.join(dataDir, 'tools', 'apache-ant', 'bin', 'ant');

    _createSrcMirror(dataDir);

    // Run the Ant executable
    final process =
        Process.run(pathToAntEx, _getAntArgs(dataDir), runInShell: true)
            .asStream()
            .asBroadcastStream();
    process.listen((data) {
      stdout.writeln(data.stdout);
    }, onError: (error) {
      stderr.writeln(error);
    });
  }

  // Generates a list of arguments for Ant
  List _getAntArgs(String dataDir) {
    final args = <String>[];
    args.add('-q');
    args.add(
        '-buildfile=${path.join(dataDir, 'tools', 'apache-ant', 'build.xml')}');

    args.add('-Dout=${path.join(_currentDir, 'out')}');
    args.add('-Dextension=$_extType');
    args.add('-DextSrc=${path.join(dataDir, 'workspaces', _extType, 'temp')}');

    args.add(
        '-Dclasses=${path.join(dataDir, 'workspaces', _extType, 'classes')}');
    args.add(
        '-DrawCls=${path.join(dataDir, 'workspaces', _extType, 'raw-classes')}');
    args.add('-Draw=${path.join(dataDir, 'workspaces', _extType, 'raw')}');

    args.add('-Dai=${path.join(_currentDir, 'dev-deps')}');
    args.add('-Ddeps=${path.join(_currentDir, 'dependencies')}');

    args.add('-Ddexer=${path.join(dataDir, 'tools', 'dx.jar')}');
    args.add(
        '-DantCon=${path.join(dataDir, 'tools', 'ant-contrib-1.0b3.jar')}');

    return args;
  }

  /// Creates exact copy of the extension src directory in the Rush Data Dir.
  /// This is done to add the annotations eliminated by rush.yaml to the Java
  /// source file of the extensions.
  void _createSrcMirror(String dataDirPath) {
    //? Dev note:
    // Yes, this is, in fact, a very inefficient thing to do in terms of 
    // performance, as well as memory consumption, etc. But I'm just way to lazy
    // to try out any solution.
    // This can be solved by, maybe, writing a different ComponentProcessor, which
    // could generate the component.json from the designer props provided to it as
    // args.

    final extSrcDir = Directory(path.join(_currentDir, 'src'));
    final mirrorDir =
        Directory(path.join(dataDirPath, 'workspaces', _extType, 'temp'));
    mirrorDir.createSync(recursive: true);
    copyDir(extSrcDir, mirrorDir);

    final rushYmlRaw =
        File(path.join(_currentDir, 'rush.yaml')).readAsStringSync();
    final rushYml = loadYaml(rushYmlRaw);

    final designerComp = DesignerComponent(
      category: 'ComponentCategory.EXTENSION',
      desc: rushYml['description'],
      helpUrl: rushYml['homepage'],
      iconName: rushYml['assets']['icon'],
      license: rushYml['license'],
      minSdk: int.tryParse(rushYml['minSdk'] ?? '7'),
      nonVisible:
          true, //? Until the release of visible ext, this will be hard coded
      version: rushYml['version']['number'] == 'auto'
          ? _getVersion
          : rushYml['version']['number'],
      versionName: rushYml['version']['name'],
    ).toString();

    // TODO: Create @UsesAssets

    // The actual ext src file
    final extFile = File(path.joinAll(
        [extSrcDir.path, ..._extType.split('.'), '${rushYml['name']}.java']));
    final ext = extFile.readAsLinesSync();

    final simpleObjPattern =
        RegExp(r'@SimpleObject\s?\(\s?external\s?=\s?true\)');
    final index = ext.indexWhere((line) => line.contains(simpleObjPattern));
    final replacement = ext[index].replaceAll(
        simpleObjPattern, '$designerComp\n@SimpleObject(external=true)');

    ext.removeAt(index);
    ext.insert(index, replacement);

    // The duplicate ext src file
    File(path.joinAll([
      mirrorDir.path,
      ..._extType.split('.'),
      '${rushYml['name']}.java'
    ])).writeAsStringSync(ext.join('\n'));
  }

  int get _getVersion =>
      1; // TODO: Auto increament version number after each build.
}
