import 'dart:io' show Directory, exit;

import 'package:args/command_runner.dart';
import 'package:dart_console/dart_console.dart';
import 'package:rush_cli/commands/build/build.dart';
import 'package:rush_cli/commands/clean.dart';
import 'package:rush_cli/commands/create.dart';
import 'package:rush_cli/commands/migrate.dart';
import 'package:rush_cli/commands/upgrade/upgrade.dart';
import 'package:rush_cli/utils/dir_utils.dart';
import 'package:rush_cli/services/file_service.dart';
import 'package:rush_cli/version.dart';
import 'package:rush_prompt/rush_prompt.dart';

void main(List<String> args) {
  final runner = RushCommandRunner(
      'rush', 'A new and improved way of building App Inventor 2 extensions.');

  runner.argParser.addFlag('version', abbr: 'v', negatable: false,
      callback: (val) {
    if (val) {
      _printVersion();
    }
  });

  final fs = FileService(Directory.current.path, DirUtils.dataDir()!);

  runner
    ..addCommand(CreateCommand(fs))
    ..addCommand(BuildCommand(fs))
    ..addCommand(MigrateCommand(fs))
    ..addCommand(UpgradeCommand(fs.dataDir))
    ..addCommand(CleanCommand(fs));

  runner.run(args).catchError((Object err) {
    if (err is UsageException) {
      runner.printUsage();
    } else {
      throw err;
    }
  });
}

void _printVersion() {
  PrintArt();
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

class RushCommandRunner extends CommandRunner<void> {
  RushCommandRunner(String executableName, String description)
      : super(executableName, description);

  @override
  void printUsage() {
    PrintArt();

    final console = Console();
    // Print description
    console..writeLine(' ' + description)..writeLine();

    // Print usage
    console
      ..writeLine(' Usage: ')
      ..setForegroundColor(ConsoleColor.brightBlue)
      ..write('   rush ')
      ..setForegroundColor(ConsoleColor.cyan)
      ..write('[command]')
      ..setForegroundColor(ConsoleColor.yellow)
      ..writeLine(' <arguments>')
      ..resetColorAttributes()
      ..writeLine();

    // Print global options
    console
      ..writeLine(' Global options:')
      ..setForegroundColor(ConsoleColor.yellow)
      ..write('   -h, --help')
      ..resetColorAttributes()
      ..writeLine('     Prints usage information.')
      ..resetColorAttributes()
      ..writeLine();

    final cmdNamesSorted = commands.keys.toList()..sort();
    final width = cmdNamesSorted.last.length;

    console.writeLine(' Available commands:');
    for (final command in commands.values) {
      console
        ..setForegroundColor(ConsoleColor.cyan)
        ..write(command.name.padLeft(width))
        ..resetColorAttributes()
        ..write('  ')
        ..writeLine(command.description);
    }
  }
}
