// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:tint/tint.dart';

class Logger {
  int _errorCount = 0;
  int get errorCount => _errorCount;

  int _warningCount = 0;
  int get warningCount => _warningCount;

  bool _isStepInit = false;

  void initStep(String title) {
    if (!_isStepInit) {
      print('┌─ '.brightBlack() + title);
      _isStepInit = true;
    } else {
      debug('Attempted to init a new step before closing previous' +
          '\n' +
          StackTrace.current.toString());
    }
  }

  void closeStep({bool fail = false}) {
    if (_isStepInit) {
      print('└ '.brightBlack() + (fail ? 'failed'.red() : 'done'.green()));
      _isStepInit = false;
    } else {
      debug('Attempted to close a step that was not initialized' +
          '\n' +
          StackTrace.current.toString());
    }
  }

  void log(String message, [String prefix = '     ']) {
    final prefixNew = '${_isStepInit ? '│ '.brightBlack() : ''}$prefix ';
    print(prefixNew + message);
  }

  void debug(String message, [bool printPrefix = true]) {
    log(_padMessage(message), printPrefix ? 'debug'.cyan() : '');
  }

  void info(String message, [bool printPrefix = true]) {
    log(_padMessage(message), printPrefix ? ' info'.blue() : '');
  }

  void warn(String message, [bool printPrefix = true]) {
    log(_padMessage(message), printPrefix ? ' warn'.yellow() : '');
    _warningCount++;
  }

  void error(String message, [bool printPrefix = true]) {
    log(_padMessage(message), printPrefix ? 'error'.red() : '');
    _errorCount++;
  }

  String _padMessage(String message) {
    final lines = LineSplitter.split(message).toList();
    if (lines.length == 1) {
      return message;
    }
    final sublist = lines.sublist(1).map((el) {
      if (_isStepInit) {
        return '│ '.brightBlack() + ' ' * 6 + el;
      } else {
        return ' ' * 6 + el;
      }
    });
    return [lines[0], ...sublist].join('\n');
  }
}
