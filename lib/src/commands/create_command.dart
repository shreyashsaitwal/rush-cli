import 'dart:async';
import 'dart:io';

import 'package:generator/generator.dart';
import 'package:path/path.dart' as path;
import 'package:rush/src/exceptions/cli_usage_exception.dart';
import 'package:rush/src/interfaces/i_command.dart';

class CreateCommand extends ICommand {
  final Directory _currentDirectory;
  late Directory _workingDirectory;

  @override
  String get description => 'Generate a new project by Rush.';

  @override
  String get name => 'create';

  CreateCommand(this._currentDirectory) {
    argParser
      ..addOption(
        'language',
        abbr: 'l',
        help: 'The language that the extension template will be based on.',
      )
      ..addOption(
        'organization',
        abbr: 'o',
        help:
            'An organization in reverse domain name notation, used as the extension package name.',
      );
  }

  @override
  Future<int> run() async {
    late String name;

    try {
      name = argResults?.rest.first as String;

      final String workingDirectoryPath = path.join(
        _currentDirectory.path,
        name,
      );

      _workingDirectory = Directory(workingDirectoryPath);
    } on StateError {
      // A name for the project was not provided, throw [CliUsageException].
      throw CliUsageException("Not enough arguments provided.");
    }

    final Workspace workspace = Workspace(
      _workingDirectory,
      'dev.hammerhai',
      name,
      '0.1.0',
    );

    ExtensionGenerator().generate(workspace);

    print(rush.findConfigurationDirectory()?.path);

    return Future.value(0);
  }
}
