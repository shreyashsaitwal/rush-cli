import 'package:dart_console/dart_console.dart';

class BuildStep {
  final console = Console();

  final String _title;

  BuildStep(this._title);

  /// Initializes this step.
  void init() {
    console
      ..setForegroundColor(ConsoleColor.brightBlack)
      ..write('┌ ')
      ..resetColorAttributes()
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..writeLine(_title)
      ..resetColorAttributes();
  }

  /// Logs the given [msg] as a warning to this step's stdout.
  void logErr(String msg, {bool addPrefix = true, bool addSpace = false}) {
    if (addSpace) {
      console
        ..setForegroundColor(ConsoleColor.brightBlack)
        ..writeErrorLine('│ ')
        ..resetColorAttributes();
    }
    console
      ..setForegroundColor(ConsoleColor.brightBlack)
      ..write('│ ')
      ..resetColorAttributes();

    if (addPrefix) {
      console
        ..setBackgroundColor(ConsoleColor.red)
        ..setForegroundColor(ConsoleColor.brightWhite)
        ..write('ERR')
        ..resetColorAttributes()
        ..write(' ');
    }

    console
      ..setForegroundColor(ConsoleColor.red)
      ..writeErrorLine(msg)
      ..resetColorAttributes();
  }

  /// Logs the given [msg] as a warning to this step's stdout.
  void logWarn(String msg, {bool addPrefix = true, bool addSpace = false}) {
    if (addSpace) {
      console
        ..setForegroundColor(ConsoleColor.brightBlack)
        ..writeLine('│ ')
        ..resetColorAttributes();
    }
    console
      ..setForegroundColor(ConsoleColor.brightBlack)
      ..write('│ ')
      ..resetColorAttributes();

    if (addPrefix) {
      console
        ..setBackgroundColor(ConsoleColor.yellow)
        ..setForegroundColor(ConsoleColor.black)
        ..write('WARN')
        ..resetColorAttributes()
        ..write(' ');
    }

    console
      ..setForegroundColor(ConsoleColor.yellow)
      ..writeErrorLine(msg)
      ..resetColorAttributes();
  }

  /// Logs the given [msg] to this step's stdout and optionally styles it.
  void log(String msg, ConsoleColor clr,
      {bool addSpace = false,
      String prefix = '',
      ConsoleColor prefFG = ConsoleColor.white,
      ConsoleColor prefBG = ConsoleColor.black}) {
    if (addSpace) {
      console
        ..setForegroundColor(ConsoleColor.brightBlack)
        ..writeLine('│ ')
        ..resetColorAttributes();
    }
    console
      ..setForegroundColor(ConsoleColor.brightBlack)
      ..write('│ ')
      ..resetColorAttributes();

    if (prefix != '' && prefBG != ConsoleColor.black) {
      console
        ..write(' ')
        ..setBackgroundColor(prefBG)
        ..setForegroundColor(prefFG)
        ..write(prefix)
        ..resetColorAttributes()
        ..write(' ')
        ..setForegroundColor(clr)
        ..writeLine(msg)
        ..resetColorAttributes();
    } else {
      console
        ..setForegroundColor(clr)
        ..writeLine(' ' + msg)
        ..resetColorAttributes();
    }
  }

  /// Finishes this step.
  void finishOk(String msg) {
    console
      ..setForegroundColor(ConsoleColor.brightBlack)
      ..write('└ ')
      ..resetColorAttributes()
      ..setForegroundColor(ConsoleColor.green)
      ..writeLine(msg)
      ..resetColorAttributes();
  }

  /// Finishes this step.
  void finishNotOk(String msg) {
    console
      ..setForegroundColor(ConsoleColor.brightBlack)
      ..write('└ ')
      ..resetColorAttributes()
      ..setForegroundColor(ConsoleColor.red)
      ..writeLine(msg)
      ..resetColorAttributes();
  }
}
