import 'dart:convert';

import 'package:dart_console/dart_console.dart';
import 'package:tint/tint.dart';

final _console = Console();

class Logger {
  bool debug = false;

  bool _isTaskRunning = false;
  bool _hasTaskLogged = false;
  final _taskStopwatch = Stopwatch();

  void dbg(String message) {
    if (debug) {
      log(message, 'debug '.blue());
    }
  }

  void info(String message) {
    log(message, 'info  '.cyan());
  }

  void warn(String message) {
    log(message, 'warn  '.yellow());
  }

  void err(String message) {
    log(message, 'error '.red());
  }

  final _warnRegex = RegExp('(warning:? ){1,2}', caseSensitive: false);
  final _errRegex = RegExp('(error:? ){1,2}', caseSensitive: false);
  final _exceptionRegex = RegExp('(exception:? )', caseSensitive: false);
  final _dbgRegex = RegExp('((note:? )|(debug:? )){1,2}', caseSensitive: false);
  final _infoRegex = RegExp('(info:? ){1,2}', caseSensitive: false);

  void parseAndLog(String chunk) {
    final lines = LineSplitter.split(chunk);
    for (final el in lines.toList()) {
      if (el.trim().isEmpty) {
        continue;
      }

      final String prefix;
      final String msg;
      if (_warnRegex.hasMatch(el)) {
        prefix = 'warn  '.yellow();
        msg = el.replaceFirst(_warnRegex, '');
      } else if (_errRegex.hasMatch(el)) {
        prefix = 'error '.red();
        msg = el.replaceFirst(_errRegex, '');
      } else if (_exceptionRegex.hasMatch(el)) {
        prefix = 'error '.red();
        msg = el;
      } else if (_infoRegex.hasMatch(el)) {
        prefix = 'info  '.cyan();
        msg = el.replaceFirst(_infoRegex, '');
      } else if (_dbgRegex.hasMatch(el)) {
        if (!debug) {
          continue;
        }
        prefix = 'debug '.blue();
        msg = el.replaceFirst(_dbgRegex, '');
      } else {
        prefix = ' ' * 6;
        msg = el;
      }
      log(msg.trimRight(), prefix);
    }
  }

  String _taskTitle = '';

  void log(String message, [String prefix = '']) {
    if (!_hasTaskLogged && _isTaskRunning) {
      _console
        ..cursorUp()
        ..eraseLine()
        ..write('┌ '.brightBlack() + _taskTitle)
        ..writeLine();
      _hasTaskLogged = true;
    }
    if (_isTaskRunning) {
      prefix = '│ '.brightBlack() + prefix;
    }
    _console.writeLine(prefix + message.trimRight());
  }

  void startTask(String title) {
    if (_isTaskRunning) {
      throw Exception('A task is already running');
    }
    _taskStopwatch.start();
    _isTaskRunning = true;
    _taskTitle = title;
    _console
      ..write('- '.brightBlack())
      ..write(title)
      ..writeLine();
  }

  void stopTask([bool success = true]) {
    if (!_isTaskRunning) {
      throw Exception('No task is running');
    }

    final time = (_taskStopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2);
    String line = (success ? '✓'.green() : '×'.red()) +
        ' ' * 4 +
        '... (${time}s)'.brightBlack();
    if (_hasTaskLogged) {
      line = '└ '.brightBlack() + line;
    } else {
      line = '${'- '.brightBlack()}$_taskTitle $line';
      _console
        ..cursorUp()
        ..eraseLine();
    }
    _console
      ..write(line)
      ..writeLine();

    _isTaskRunning = false;
    _hasTaskLogged = false;
    _taskStopwatch.reset();
  }
}
