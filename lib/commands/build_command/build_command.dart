import 'dart:io';

import 'package:path/path.dart' as path;

import 'package:rush_cli/commands/mixins/app_data_dir_mixin.dart';

class BuildCommand with AppDataMixin {
  BuildCommand(this._currentDir, this._extType);

  final _currentDir;
  final _extType;

  void run() {
    final dataDir = AppDataMixin.dataStorageDir();
    final pathToAntEx = path.join(dataDir, 'tools', 'apache-ant', 'bin', 'ant');
    Process.run(pathToAntEx, _getAntArgs(dataDir), runInShell: true).then((process) {
      stdout.writeln(process.stdout);
      stderr.writeln(process.stderr);
    });
  }

  List _getAntArgs(String dataDir) {
    final args = <String>[];
    args.add(
        '-buildfile=${path.join(dataDir, 'tools', 'apache-ant', 'build.xml')}');

    args.add('-Dout=${path.join(_currentDir, 'out')}');
    args.add('-Dextension=$_extType');
    args.add('-DextSrc=${path.join(_currentDir, 'src')}');

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
}
