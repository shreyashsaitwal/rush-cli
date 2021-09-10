import 'dart:io' show Directory, exit;

import 'package:args/command_runner.dart';
import 'package:dart_console/dart_console.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/commands/build/build.dart';
import 'package:rush_cli/commands/build/hive_adapters/build_box.dart';
import 'package:rush_cli/commands/clean.dart';
import 'package:rush_cli/commands/create.dart';
import 'package:rush_cli/commands/deps/deps.dart';
import 'package:rush_cli/commands/migrate.dart';
import 'package:rush_cli/commands/upgrade/upgrade.dart';
import 'package:rush_cli/utils/dir_utils.dart';
import 'package:rush_cli/services/file_service.dart';
import 'package:rush_cli/version.dart';

void main(List<String> args) {
  _printArt();
  final commandRunner = RushCommandRunner(
      'rush', 'A new and improved way of building App Inventor 2 extensions.');

  commandRunner.argParser.addFlag('version', abbr: 'v', negatable: false,
      callback: (val) {
    if (val) {
      _printVersion();
    }
  });

  final fs = FileService(Directory.current.path, DirUtils.dataDir()!);

  Hive
    ..init(p.join(fs.cwd, '.rush'))
    ..registerAdapter(BuildBoxAdapter());

  commandRunner
    ..addCommand(CreateCommand(fs))
    ..addCommand(BuildCommand(fs))
    ..addCommand(MigrateCommand(fs))
    ..addCommand(UpgradeCommand(fs.dataDir))
    ..addCommand(CleanCommand(fs))
    ..addCommand(DepsCommand(fs));

  commandRunner.run(args).catchError((Object err) {
    if (err is UsageException) {
      commandRunner.printUsage();
    } else {
      throw Exception(err);
    }
  });
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

  final console = Console();
  console.setForegroundColor(ConsoleColor.brightBlue);
  art.split('\n').forEach((ln) => console.writeLine(ln));
  console.resetColorAttributes();
}

class RushCommandRunner extends CommandRunner<void> {
  RushCommandRunner(String executableName, String description)
      : super(executableName, description);

  @override
  void printUsage() {
    final console = Console();
    // Print description
    console
      ..writeLine(' ' + description)
      ..writeLine();

    // Print usage
    console
      ..writeLine(' Usage: ')
      ..setForegroundColor(ConsoleColor.brightBlue)
      ..write('   rush ')
      ..setForegroundColor(ConsoleColor.cyan)
      ..write('<command> ')
      ..setForegroundColor(ConsoleColor.yellow)
      ..writeLine('[arguments]')
      ..resetColorAttributes()
      ..writeLine();

    // Print global options
    console
      ..writeLine(' Global options:')
      ..setForegroundColor(ConsoleColor.yellow)
      ..write('   -h, --help')
      ..resetColorAttributes()
      ..writeLine('  Prints usage information.')
      ..resetColorAttributes()
      ..writeLine();

    final cmdNamesSorted = commands.keys.toList()..sort();
    final width = cmdNamesSorted.last.length;

    console.writeLine(' Available commands:');
    for (final command in commands.values.toList(growable: true)
      ..removeWhere((el) => el.name == 'help')) {
      console
        ..setForegroundColor(ConsoleColor.cyan)
        ..write(' ' * 3 + command.name.padLeft(width))
        ..resetColorAttributes()
        ..writeLine('  ' + command.description);
    }
  }
}
