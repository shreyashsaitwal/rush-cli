import 'package:dart_console/dart_console.dart';
import 'package:rush_prompt/rush_prompt.dart';
import 'package:rush_prompt/src/err_warn_store.dart';

class BuildStep {
  final _console = Console();
  final String _title;

  BuildStep(this._title);

  LogType? prevLogType;

  /// Initializes this step.
  void init() {
    _console
      ..setForegroundColor(ConsoleColor.brightBlack)
      ..write('┌ ')
      ..resetColorAttributes()
      ..writeLine(_title);
  }

  void log(LogType type, String msg, {bool addPrefix = true}) {
    if (prevLogType != null && prevLogType != type) {
      _printPipe(fullLine: true);
    }
    prevLogType = type;
    _printPipe();

    Logger.log(type, msg, addPrefix: addPrefix);
  }

  void _printPipe({bool fullLine = false}) {
    _console.setForegroundColor(ConsoleColor.brightBlack);
    if (fullLine) {
      _console.writeLine('│ ');
    } else {
      _console.write('│ ');
    }
    _console.resetColorAttributes();
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
