import 'dart:io' show Directory, exit;

import 'package:rush_cli/commands/build/build.dart';
import 'package:rush_cli/commands/clean.dart';
import 'package:rush_cli/commands/create/create.dart';
import 'package:rush_cli/commands/deps/deps.dart';
import 'package:rush_cli/commands/migrate/migrate.dart';
import 'package:rush_cli/commands/rush_command.dart';
import 'package:rush_cli/commands/upgrade/upgrade.dart';
import 'package:rush_cli/services/service_locator.dart';
import 'package:rush_cli/version.dart';
import 'package:tint/tint.dart';

Future<void> main(List<String> args) async {
  _printArt();

  final commandRunner = RushCommandRunner();
  commandRunner.argParser
    ..addFlag('version',
        abbr: 'v',
        negatable: false,
        help: 'Prints the version info of the current installation of Rush.',
        callback: (val) {
      if (val) {
        _printVersion();
      }
    })
    ..addFlag(
      'debug',
      abbr: 'd',
      help: 'Prints debug information.',
    );

  setupServiceLocator(
      Directory.current.path, args.contains('-d') || args.contains('--debug'));

  commandRunner
    ..addCommand(BuildCommand())
    ..addCommand(CleanCommand())
    ..addCommand(CreateCommand())
    ..addCommand(DepsCommand())
    ..addCommand(MigrateCommand())
    ..addCommand(UpgradeCommand());
  await commandRunner.run(args);
}

void _printVersion() {
  print('Version: ${packageVersion.cyan()}');
  exit(0);
}

void _printArt() {
  const art = r'''
                    __
   _______  _______/ /_
  / ___/ / / / ___/ __ \
 / /  / /_/ (__  / / / /
/_/   \__,_/____/_/ /_/
''';

  print(art.blue());
}
