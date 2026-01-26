import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:json_serializer/json_serializer.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

import 'serializable/configuration.dart';

class Workspace {
  late final Directory _workingDirectory;
  late final String _groupId;
  late final String _name;
  late final String _version;

  Directory get directory => _workingDirectory;
  String get name => _name;
  String get packageName => "$_groupId.$_name";
  Directory get sourceDirectory => _getSourceDirectory();
  String get version => _version;

  Directory _getSourceDirectory() {
    String packageNameDirectoryPath = [
      ..._groupId.split('.'),
      _name.toLowerCase(),
    ].join('/');
    String sourceDirectoryPath = path.join('src', packageNameDirectoryPath);

    return Directory(sourceDirectoryPath);
  }

  Workspace(this._workingDirectory, this._groupId, this._name, this._version);

  FutureOr<Configuration?> getConfiguration() async {
    final filePath = path.join(directory.path, 'rush.yaml');
    final file = File(filePath);

    if (await file.exists() == false) {
      return Future.error('Not a Rush-based workspace');
    }

    final fileContent = await file.readAsString();

    try {
      final configuration = loadYaml(fileContent);
      final json = jsonEncode(configuration);

      return deserialize<Configuration>(json);
    } catch (exception) {
      return Future.value(null);
    }
  }
}
