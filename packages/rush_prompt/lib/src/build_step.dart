import 'package:dart_console/dart_console.dart';

class BuildStep {
  final _console = Console();

  final String _title;

  BuildStep(this._title);

  /// Initializes this step.
  void init() {
    _console
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
      _console
        ..setForegroundColor(ConsoleColor.brightBlack)
        ..writeErrorLine('│ ')
        ..resetColorAttributes();
    }
    _console
      ..setForegroundColor(ConsoleColor.brightBlack)
      ..write('│ ')
      ..resetColorAttributes();

    if (addPrefix) {
      _console
        ..setBackgroundColor(ConsoleColor.red)
        ..setForegroundColor(ConsoleColor.brightWhite)
        ..write('ERR')
        ..resetColorAttributes()
        ..write(' ');
    }

    _console
      ..setForegroundColor(ConsoleColor.red)
      ..writeErrorLine(msg)
      ..resetColorAttributes();
  }

  /// Logs the given [msg] as a warning to this step's stdout.
  void logWarn(String msg, {bool addPrefix = true, bool addSpace = false}) {
    if (addSpace) {
      _console
        ..setForegroundColor(ConsoleColor.brightBlack)
        ..writeLine('│ ')
        ..resetColorAttributes();
    }
    _console
      ..setForegroundColor(ConsoleColor.brightBlack)
      ..write('│ ')
      ..resetColorAttributes();

    if (addPrefix) {
      _console
        ..setBackgroundColor(ConsoleColor.yellow)
        ..setForegroundColor(ConsoleColor.black)
        ..write('WARN')
        ..resetColorAttributes()
        ..write(' ');
    }

    _console
      ..setForegroundColor(ConsoleColor.yellow)
      ..writeErrorLine(msg)
      ..resetColorAttributes();
  }

  /// Logs the given [msg] to this step's stdout and optionally styles it.
  void log(String msg, ConsoleColor clr,
      {bool addSpace = false,
      String prefix = '',
      ConsoleColor? prefixFG,
      ConsoleColor? prefixBG}) {
    if (addSpace) {
      _console
        ..setForegroundColor(ConsoleColor.brightBlack)
        ..writeLine('│ ')
        ..resetColorAttributes();
    }

    _console
      ..setForegroundColor(ConsoleColor.brightBlack)
      ..write('│ ')
      ..resetColorAttributes();

    if (prefixBG != null) {
      _console.setBackgroundColor(prefixBG);
    }
    if (prefixFG != null) {
      _console.setForegroundColor(prefixFG);
    }

    _console
      ..write(prefix)
      ..resetColorAttributes()
      ..write(' ')
      ..setForegroundColor(clr)
      ..writeLine(msg)
      ..resetColorAttributes();
  }

  /// Finishes this step.
  void finishOk({String? msg}) {
    _console
      ..setForegroundColor(ConsoleColor.brightBlack)
      ..write('└ ')
      ..resetColorAttributes()
      ..setForegroundColor(ConsoleColor.green)
      ..writeLine(msg ?? 'Done')
      ..resetColorAttributes();
  }

  /// Finishes this step.
  void finishNotOk({String? msg}) {
    _console
      ..setForegroundColor(ConsoleColor.brightBlack)
      ..write('└ ')
      ..resetColorAttributes()
      ..setForegroundColor(ConsoleColor.red)
      ..writeLine(msg ?? 'Failed')
      ..resetColorAttributes();
  }
}
