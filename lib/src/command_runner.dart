import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:dart_console/dart_console.dart';
import 'package:get_it/get_it.dart';
import 'package:tint/tint.dart';

import 'package:rush/src/commands/build/build.dart';
import 'package:rush/src/commands/clean.dart';
import 'package:rush/src/commands/create/create.dart';
import 'package:rush/src/commands/deps/deps.dart';
import 'package:rush/src/commands/migrate/migrate.dart';
import 'package:rush/src/commands/upgrade/upgrade.dart';
import 'package:rush/src/services/logger.dart';
import 'package:rush/src/version.dart';

class RushCommandRunner extends CommandRunner<int> {
  RushCommandRunner()
      : super('rush',
            'Rush is a fast and feature rich extension builder for MIT App Inventor 2.') {
    argParser
      ..addFlag(
        'verbose',
        abbr: 'v',
        negatable: false,
        help: 'Turns on verbose logging.',
        callback: (ok) {
          GetIt.I<Logger>().debug = ok;
        },
      )
      ..addFlag(
        'color',
        abbr: 'c',
        defaultsTo: true,
        help:
            'Whether output should be colorized or not. Defaults to true in terminals that support ANSI colors.',
      )
      ..addFlag(
        'version',
        abbr: 'V',
        negatable: false,
        help: 'Prints the current version name.',
        callback: (ok) {
          if (ok) {
            Console().writeLine('Running on version ${packageVersion.cyan()}');
            exit(0);
          }
        },
      )
      ..addFlag(
        'logo',
        abbr: 'l',
        defaultsTo: true,
        hide: true,
      );

    addCommand(BuildCommand());
    addCommand(CleanCommand());
    addCommand(CreateCommand());
    addCommand(DepsCommand());
    addCommand(MigrateCommand());
    addCommand(UpgradeCommand());
  }

  @override
  Future<int?> runCommand(ArgResults topLevelResults) {
    supportsAnsiColor = _useColor(topLevelResults);
    if (topLevelResults.command != null &&
        topLevelResults['logo'] as bool &&
        stdout.hasTerminal) {
      _printLogo();
    }
    return super.runCommand(topLevelResults);
  }

  bool _useColor(ArgResults results) {
    if (results.wasParsed('color')) {
      return results['color'] as bool;
    }
    final noColor = Platform.environment['NO_COLOR'] ?? '';
    return noColor.isEmpty && stdout.supportsAnsiEscapes;
  }

  void _printLogo() {
    final logo = r'''
                    __
   _______  _______/ /_
  / ___/ / / / ___/ __ \
 / /  / /_/ (__  / / / /
/_/   \__,_/____/_/ /_/
''';
    Console().writeLine(logo.blue());
  }
}
