import 'dart:io' show Directory, exit;

import 'package:args/command_runner.dart';
import 'package:dart_console/dart_console.dart';
import 'package:rush_cli/commands/build_command/build_command.dart';
import 'package:rush_cli/commands/create_command/create_command.dart';
import 'package:rush_cli/commands/migrate_command/migrate_command.dart';
import 'package:rush_cli/commands/upgrade_command/upgrade_command.dart';
import 'package:rush_cli/helpers/app_data_dir.dart';
import 'package:rush_cli/version.dart';
import 'package:rush_prompt/rush_prompt.dart';

void main(List<String> args) {
  final _cd = Directory.current.path;
  final _dataDir = RushDataDir.dataDir()!;

  final runner = RushCommandRunner(
      'rush', 'A new and improved way of building App Inventor 2 extensions.');

  runner.argParser.addFlag('version', abbr: 'v', negatable: false,
      callback: (val) {
    if (val) {
      _printVersion();
    }
  });

  runner
    ..addCommand(CreateCommand(_cd, _dataDir))
    ..addCommand(BuildCommand(_cd, _dataDir))
    ..addCommand(MigrateCommand(_cd, _dataDir))
    ..addCommand(UpgradeCommand(_dataDir))
    ..run(args).catchError((err) {
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
    ..setForegroundColor(ConsoleColor.brightWhite)
    ..write('Version:   ')
    ..setForegroundColor(ConsoleColor.cyan)
    ..writeLine(rushVersion)
    ..setForegroundColor(ConsoleColor.brightWhite)
    ..write('Built on:  ')
    ..setForegroundColor(ConsoleColor.cyan)
    ..writeLine(rushBuiltOn)
    ..resetColorAttributes();
  exit(0);
}

class RushCommandRunner extends CommandRunner {
  RushCommandRunner(String executableName, String description)
      : super(executableName, description);

  @override
  void printUsage() {
    PrintArt();

    final console = Console();
    // Print description
    console
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..writeLine(' ' + description)
      ..writeLine();

    // Print usage
    console
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..writeLine(' Usage: ')
      ..setForegroundColor(ConsoleColor.brightBlue)
      ..write('   rush ')
      ..setForegroundColor(ConsoleColor.cyan)
      ..write('[command]')
      ..setForegroundColor(ConsoleColor.yellow)
      ..writeLine(' <arguments>')
      ..writeLine();

    // Print global options
    console
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..writeLine(' Global options:')
      ..setForegroundColor(ConsoleColor.yellow)
      ..write('   -h, --help')
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..writeLine('     Prints usage information.')
      ..resetColorAttributes()
      ..writeLine();

    // Print available commands
    console
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..writeLine(' Available commands:')
      ..setForegroundColor(ConsoleColor.cyan)
      ..write('    build')
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..writeLine(
          '  Identifies and builds the extension project in current working directory.')
      ..setForegroundColor(ConsoleColor.cyan)
      ..write('   create')
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..writeLine(
          '  Scaffolds a new extension project in current working directory.')
      ..setForegroundColor(ConsoleColor.cyan)
      ..write('  migrate')
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..writeLine(
          '  Introspects and migrates the extension-template project in CWD to Rush.')
      ..setForegroundColor(ConsoleColor.cyan)
      ..write('  upgrade')
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..writeLine(
          '  Upgrades Rush and all it\'s components to the latest available version.')
      ..resetColorAttributes();
  }
}
