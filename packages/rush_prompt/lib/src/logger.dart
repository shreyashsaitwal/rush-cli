import 'package:dart_console/dart_console.dart';
import 'package:rush_prompt/src/err_warn_store.dart';

enum LogType { erro, warn, info, note }

class Logger {
  static final _console = Console();
  static final _errWarnStore = ErrWarnStore();

  static void log(LogType type, String msg, {bool addPrefix = true}) {
    final printPrefix = (ConsoleColor clr, String prefix) {
      _console
        ..setForegroundColor(clr)
        ..write(prefix)
        ..resetColorAttributes()
        ..write(' ');
    };

    if (addPrefix) {
      switch (type) {
        case LogType.erro:
          printPrefix(ConsoleColor.red, '[erro]');
          _errWarnStore.incErrors();
          break;
        case LogType.warn:
          printPrefix(ConsoleColor.yellow, '[warn]');
          _errWarnStore.incWarnings();
          break;
        case LogType.note:
          printPrefix(ConsoleColor.blue, '[note]');
          break;
        default:
          printPrefix(ConsoleColor.cyan, '[info]');
          break;
      }
    }

    if (type == LogType.erro) {
      _console.writeErrorLine(msg);
    } else {
      _console.writeLine(msg);
    }
  }

  /// Logs the given [message] to the stdout and optionally styles it.
  static void logCustom(
    String message, {
    ConsoleColor? color,
    String prefix = '',
    ConsoleColor? prefixFG,
  }) {
    if (prefixFG != null) {
      _console.setForegroundColor(prefixFG);
    }

    _console
      ..write(prefix)
      ..resetColorAttributes();

    if (color != null) {
      _console.setForegroundColor(color);
    }

    _console
      ..writeLine(message)
      ..resetColorAttributes();
  }
}
