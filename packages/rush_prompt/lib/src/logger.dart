import 'dart:io';

import 'package:dart_console/dart_console.dart';

class Logger {
  /// Logs the given [message] to the stdout in red color and optionally adds a prefix
  /// (ERR) in front of it.
  static void logErr(String message,
      {bool addPrefix = true, bool addSpace = false, int? exitCode}) {
    final console = Console();

    if (addPrefix) {
      console
        ..write(addSpace ? '\n' : '')
        ..setBackgroundColor(ConsoleColor.red)
        ..setForegroundColor(ConsoleColor.brightWhite)
        ..write('ERR')
        ..resetColorAttributes()
        ..write(' ');
    }

    console
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..writeErrorLine(message)
      ..resetColorAttributes();

    if (exitCode != null) {
      exit(exitCode);
    }
  }

  static void logWarn(String message,
      {bool addPrefix = true, bool addSpace = false}) {
    final console = Console();

    if (addPrefix) {
      console
        ..write(addSpace ? '\n' : '')
        ..setBackgroundColor(ConsoleColor.yellow)
        ..setForegroundColor(ConsoleColor.black)
        ..write('ERR')
        ..resetColorAttributes()
        ..write(' ');
    }

    console
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..writeErrorLine(message)
      ..resetColorAttributes();
  }

  /// Logs the given [message] to the stdout and optionally styles it.
  static void log(
    String message, {
    ConsoleColor color = ConsoleColor.brightWhite,
    String prefix = '',
    ConsoleColor prefixFG = ConsoleColor.brightWhite,
    ConsoleColor prefixBG = ConsoleColor.brightBlack,
  }) {
    Console()
      ..setBackgroundColor(prefixBG)
      ..setForegroundColor(prefixFG)
      ..write(prefix)
      ..resetColorAttributes()
      ..setForegroundColor(color)
      ..writeLine(message)
      ..resetColorAttributes();
  }
}
