import 'package:args/command_runner.dart';
import 'package:dart_console/dart_console.dart';
import 'package:rush_cli/commands/deps/sync.dart';
import 'package:rush_cli/commands/deps/tree.dart';
import 'package:rush_cli/services/file_service.dart';

class DepsCommand extends Command<void> {
  final FileService _fs;

  DepsCommand(this._fs) {
    addSubcommand(DepsTreeCommand(_fs));
    addSubcommand(DepsSyncCommand(_fs));
  }

  @override
  String get description => 'Work with project dependencies.';

  @override
  String get name => 'deps';

  @override
  void printUsage() {
    final console = Console();
    console
      ..setForegroundColor(ConsoleColor.cyan)
      ..write(' deps ')
      ..resetColorAttributes()
      ..writeLine(description)
      ..writeLine()
      ..write(' Usage: ')
      ..setForegroundColor(ConsoleColor.brightBlue)
      ..write('rush ')
      ..setForegroundColor(ConsoleColor.cyan)
      ..write('deps ')
      ..write('[subcommand] ')
      ..setForegroundColor(ConsoleColor.yellow)
      ..writeLine('<flags>')
      ..resetColorAttributes()
      ..writeLine();

    final cmdNamesSorted = subcommands.keys.toList()..sort();
    final width = cmdNamesSorted.last.length;

    console.writeLine(' Available subcommands:');
    for (final command in subcommands.values) {
      console
        ..setForegroundColor(ConsoleColor.cyan)
        ..write(' ' * 3 + command.name.padLeft(width))
        ..resetColorAttributes()
        ..writeLine('  ' + command.description);
    }
  }
}
