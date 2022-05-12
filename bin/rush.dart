import 'dart:io' show Directory, exit;

import 'package:dart_console/dart_console.dart';
import 'package:rush_cli/commands/build/build.dart';
import 'package:rush_cli/commands/clean.dart';
import 'package:rush_cli/commands/create.dart';
import 'package:rush_cli/commands/deps/deps.dart';
import 'package:rush_cli/commands/migrate.dart';
import 'package:rush_cli/commands/rush_command.dart';
import 'package:rush_cli/commands/upgrade/upgrade.dart';
import 'package:rush_cli/utils/dir_utils.dart';
import 'package:rush_cli/services/file_service.dart';
import 'package:rush_cli/version.dart';

Future<void> main(List<String> args) async {
  _printArt();

  final commandRunner = RushCommandRunner();
  commandRunner.argParser.addFlag('version',
      abbr: 'v',
      negatable: false,
      help: 'Prints the version info of the current installation of Rush.',
      callback: (val) {
    if (val) {
      _printVersion();
    }
  });

  final fs = FileService(Directory.current.path, DirUtils.dataDir()!);
  print(fs.cwd);

  commandRunner
    ..addCommand(CreateCommand(fs))
    ..addCommand(BuildCommand(fs))
    ..addCommand(MigrateCommand(fs))
    ..addCommand(UpgradeCommand(fs.dataDir))
    ..addCommand(CleanCommand(fs))
    ..addCommand(DepsCommand(fs));

  try {
    await commandRunner.run(args);
  } catch (e, s) {
    print(s);
    rethrow;
  }
}

void _printVersion() {
  Console()
    ..write('Version:   ')
    ..setForegroundColor(ConsoleColor.cyan)
    ..writeLine(rushVersion)
    ..resetColorAttributes()
    ..write('Built on:  ')
    ..setForegroundColor(ConsoleColor.cyan)
    ..writeLine(rushBuiltOn)
    ..resetColorAttributes();
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

  Console()
    ..setForegroundColor(ConsoleColor.brightBlue)
    ..writeLine(art)
    ..resetColorAttributes();
}
