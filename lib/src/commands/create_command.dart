import 'dart:async';
import 'dart:io';

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

    // TODO: This is how the extension template will be generated.
    // final Workspace workspace = Workspace(
    //   _workingDirectory,
    //   'com.github',
    //   name,
    //   '0.1.0',
    // );
    //
    // workspace.generateExtensionTemplates();

    return Future.value(0);
  }
}
