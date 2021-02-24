import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:dart_console/dart_console.dart';
import 'package:rush_cli/commands/build_command/build_command.dart';
import 'package:rush_cli/commands/create_command/create_command.dart';
import 'package:rush_prompt/rush_prompt.dart';

const VERSION = 'v0.51';
const DATE_BLT = '23-02-2021';

final cd = Directory.current.path;

void main(List<String> args) {
  final parser = ArgParser()..addFlag('version', abbr: 'v', negatable: false);
  if (parser.parse(args).wasParsed('version')) {
    PrintArt();
    Console()
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..write('Version:  ')
      ..setForegroundColor(ConsoleColor.cyan)
      ..writeLine(VERSION)
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..write('Built on: ')
      ..setForegroundColor(ConsoleColor.cyan)
      ..writeLine(DATE_BLT);
    exit(0);
  }

  final runner = RushCommandRunner(
      'rush', 'A new and improved way of building App Inventor 2 extensions.');

  runner
    ..addCommand(CreateCommand(cd))
    ..addCommand(BuildCommand(cd))
    ..run(args).catchError((err) {
      if (err is UsageException) {
        runner.printUsage();
      } else {
        throw err;
      }
    });
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
      ..write('   build')
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..writeLine(
          '          Identifies and builds the extension project in current working directory.')
      ..setForegroundColor(ConsoleColor.cyan)
      ..write('   create')
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..writeLine(
          '         Scaffolds a new extension project in current working directory.')
      ..resetColorAttributes();
  }
}
