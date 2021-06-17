import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:process_runner/process_runner.dart';
import 'package:rush_prompt/rush_prompt.dart';

enum Result { ok, error }

class ProcessResult {
  late final Result _result;
  late final ErrWarnStore _errWarnStore;

  ProcessResult();

  ProcessResult._init(this._result, this._errWarnStore);

  Result get result => _result;
  ErrWarnStore get store => _errWarnStore;
}

class ProcessPatternChecker {
  final RegExp _pattern;
  late final bool _exists;

  ProcessPatternChecker(this._pattern);

  RegExp get pattern => _pattern;

  bool get patternExists => _exists;
  // ignore: unused_element
  set _patternExists(value) => _exists = value;
}

class ProcessStreamer {
  /// Starts a process from given [args] and returns a stream of events
  /// emitted by that process.
  static Future<ProcessResult> stream(
    List<String> args,
    String cd,
    BuildStep step, {
    Directory? workingDirectory,
    ProcessPatternChecker? patternChecker,
    bool isProcessIsolated = false,
    bool printNormalOutputAlso = false,
  }) async {
    // These patterns are either useless or don't make sense in Rush's
    // context. For example, the error and warning count printed by
    // javac is not necessary to print as Rush itself keeps track of
    // them.
    final excludePatterns = [
      RegExp(r'The\sfollowing\soptions\swere\snot\srecognized'),
      RegExp(r'\d+\s*warnings?\s?'),
      RegExp(r'\d+\s*errors?\s?'),
      RegExp(r'.*Recompile\swith.*for\sdetails', dotAll: true)
    ];

    final process = ProcessRunner()
        .runProcess(args, workingDirectory: workingDirectory)
        .asStream()
        .asBroadcastStream();

    try {
      await for (final data in process) {
        final stdout = data.stdout.split('\n');

        // Checks if a particular string that matches the pattern
        // exists in stdout. This is specifically required for
        // checking if de-jetification is necessary.
        if (patternChecker != null) {
          final pattern = patternChecker.pattern;
          patternChecker._exists = stdout.any((el) => el.contains(pattern));
        }

        if (printNormalOutputAlso) {
          final outputLines = stdout.where((line) =>
              line.trim().isNotEmpty &&
              !excludePatterns.any((el) => el.hasMatch(line)));

          _printToTheConsole(outputLines.toList(), cd, step, isProcessIsolated);
        }
      }

      return ProcessResult._init(Result.ok, ErrWarnStore());
    } on ProcessRunnerException catch (e) {
      final stderr = e.result?.stderr.split('\n') ?? [];
      final errorLines = stderr.where((line) =>
          line.trim().isNotEmpty &&
          !excludePatterns.any((el) => el.hasMatch(line)));

      _printToTheConsole(errorLines.toList(), cd, step, isProcessIsolated);

      return ProcessResult._init(Result.error, ErrWarnStore());
    }
  }

  /// This list keeps a track of the errors/warnings/etc. that have
  /// been printed already.
  static final _alreadyPrinted = <String>[];

  /// Prints [outputLines] to the console with appropriate [LogType].
  static void _printToTheConsole(List<String> outputLines, String cd,
      BuildStep step, bool stackAlreadyPrinted) {
    final patterns = <LogType, RegExp>{
      LogType.erro: RegExp(r'(\s*error:\s?)+', caseSensitive: false),
      LogType.warn: RegExp(r'(\s*warning:\s?)+', caseSensitive: false),
      LogType.info: RegExp(r'(\s*info:\s?)+', caseSensitive: false),
      LogType.note: RegExp(r'(\s*note:\s?)+', caseSensitive: false),
    };

    var skipThisErrStack = false;
    var pervLogType = LogType.warn;

    for (var line in outputLines) {
      final MapEntry<LogType, RegExp>? type;
      if (patterns.values.any((el) => line.contains(el))) {
        type = patterns.entries.firstWhere((el) => line.contains(el.value));
      } else {
        type = null;
      }

      if (stackAlreadyPrinted && _alreadyPrinted.contains(line)) {
        skipThisErrStack = true;
        continue;
      }

      if (type != null) {
        line = line.replaceFirst(
            type.value, line.startsWith(type.value) ? '' : ' ');

        if (line.startsWith(cd)) {
          line = line.replaceFirst(p.join(cd, 'src'), 'src');
        }

        step.log(type.key, line);
        pervLogType = type.key;

        skipThisErrStack = false;
        _alreadyPrinted.add(line);
      } else if (!skipThisErrStack) {
        if (line.startsWith(cd)) {
          line = line.replaceFirst(p.join(cd, 'src'), 'src');
        }
        step.log(pervLogType, ' ' * 5 + line, addPrefix: false);
      }
    }
  }
}
