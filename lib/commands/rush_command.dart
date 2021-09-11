import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:collection/collection.dart';
import 'package:dart_console/dart_console.dart';

abstract class RushCommand extends Command<void> {
  @override
  void printUsage() {
    final console = Console();

    // Print name and description
    console
      ..setForegroundColor(ConsoleColor.cyan)
      ..write(name + ' ')
      ..resetColorAttributes()
      ..writeLine(description)
      ..writeLine();

    // Print usage
    console
      ..write('Usage: ')
      ..setForegroundColor(ConsoleColor.blue)
      ..write('rush $name ')
      ..resetColorAttributes();
    if (subcommands.isNotEmpty) {
      console
        ..setForegroundColor(ConsoleColor.cyan)
        ..write('[subcommand] ')
        ..resetColorAttributes();
    }
    if (argParser.options.isNotEmpty) {
      console
        ..setForegroundColor(ConsoleColor.yellow)
        ..write('<options>')
        ..resetColorAttributes();
    }
    console.writeLine('');

    // Print available options
    if (argParser.options.isNotEmpty) {
      console
        ..writeLine()
        ..writeLine('Available options:');

      final longestLen = argParser.options.values
          .map((el) => _optionNameString(el))
          .max
          .length;

      for (final el in argParser.options.values) {
        console
          ..write(' ' * 2)
          ..setForegroundColor(ConsoleColor.yellow)
          ..write(_optionNameString(el).padRight(longestLen))
          ..resetColorAttributes()
          ..write(' ' * 2)
          ..writeLine(el.help);
      }
    }

    // Print subcommands
    if (subcommands.isNotEmpty) {
      console
        ..writeLine()
        ..writeLine('Available subcommands:');

      final longestLen = subcommands.keys.max.length;
      for (final el in subcommands.values) {
        console
          ..write(' ' * 2)
          ..setForegroundColor(ConsoleColor.yellow)
          ..write(el.name.padRight(longestLen))
          ..resetColorAttributes()
          ..write(' ' * 2)
          ..writeLine(el.description);
      }
    }
  }
}

class RushCommandRunner extends CommandRunner<void> {
  RushCommandRunner()
      : super(
          'rush',
          'A new and improved way of building App Inventor 2 extensions.',
        );

  @override
  void printUsage() {
    final console = Console();
    console
      ..writeLine(description)
      ..writeLine();

    // Print usage
    console
      ..write('Usage: ')
      ..setForegroundColor(ConsoleColor.blue)
      ..write('rush ')
      ..setForegroundColor(ConsoleColor.cyan)
      ..write('[command] ')
      ..setForegroundColor(ConsoleColor.yellow)
      ..writeLine('<options>')
      ..resetColorAttributes()
      ..writeLine();

    console.writeLine('Available options:');
    final longestOptLen =
        argParser.options.values.map((el) => _optionNameString(el)).max.length;

    for (final el in argParser.options.values) {
      console
        ..write(' ' * 2)
        ..setForegroundColor(ConsoleColor.yellow)
        ..write(_optionNameString(el).padRight(longestOptLen))
        ..resetColorAttributes()
        ..write(' ' * 2)
        ..writeLine(el.help);
    }

    // Print commands
    console
      ..writeLine()
      ..writeLine('Available commands:');
    final longestCmdLen = commands.keys.max.length;

    for (final el in commands.values.toList()
      ..removeWhere((el) => el.name == 'help')) {
      console
        ..write(' ' * 2)
        ..setForegroundColor(ConsoleColor.cyan)
        ..write(el.name.padRight(longestCmdLen))
        ..resetColorAttributes()
        ..write(' ' * 2)
        ..writeLine(el.description);
    }
  }
}

// Returns the option name string used while printing help text for the command.
// For e.g.: -o, --[no-]optimize
String _optionNameString(Option option) {
  var res = '-${option.abbr}';
  if (option.negatable ?? false) {
    res += ', --[no-]${option.name}';
  } else {
    res += ', --${option.name}';
  }
  return res;
}
