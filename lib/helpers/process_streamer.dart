import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:process_runner/process_runner.dart';
import 'package:rush_cli/commands/build/hive_adapters/build_box.dart';
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
  set _patternExists(bool value) => _exists = value;
}

class ProcessStreamer {
  /// Starts a process from given [args] and returns a stream of events emitted
  /// by that process.
  static Future<ProcessResult> stream(
    List<String> args,
    String cwd, {
    Directory? workingDirectory,
    ProcessPatternChecker? patternChecker,
    bool trackPreviouslyLogged = false,
    bool printNormalOutput = false,
  }) async {
    // In almost all places where this class (`ProcessStreamer`) is used, a new
    // isolate is spawned. Isolates don't allow passing objects that depends on
    // `dart:ffi` as arguments to it. Now, `BuildStep`, which builds on top of
    // `dart_console`, indirectly depends on `dart:ffi` and because of this reason
    // we don't get the required step as an argument to this method and instead
    // instantiate a new one here. This won't start a new build step; it will just
    // append messages to the existing step because we aren't calling the `init()`
    // method on it.
    final step = BuildStep('');

    // These patterns are either useless or don't make sense in Rush's context.
    // For example, the error and warning count printed by javac is not necessary
    // to print as Rush itself keeps track of them.
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
        final stdout = LineSplitter.split(data.output);

        // Checks if a particular string that matches the pattern exists in stdout.
        // This is specifically required for checking if de-jetification is
        // necessary.
        if (patternChecker != null) {
          final pattern = patternChecker.pattern;
          patternChecker._exists = stdout.any((el) => el.contains(pattern));
        }

        if (printNormalOutput) {
          final outputLines = stdout.where((line) =>
              line.trim().isNotEmpty &&
              !excludePatterns.any((el) => el.hasMatch(line)));

          await _printToTheConsole(
              outputLines.toList(), cwd, step, trackPreviouslyLogged);
        }
      }

      return ProcessResult._init(Result.ok, ErrWarnStore());
    } on ProcessRunnerException catch (e) {
      final stderr = LineSplitter.split(e.result?.stderr ?? '');
      final errorLines = stderr.where((line) =>
          line.trim().isNotEmpty &&
          !excludePatterns.any((el) => el.hasMatch(line)));

      await _printToTheConsole(
          errorLines.toList(), cwd, step, trackPreviouslyLogged);

      return ProcessResult._init(Result.error, ErrWarnStore());
    }
  }

  /// Prints [outputLines] to the console with appropriate [LogType].
  static Future<void> _printToTheConsole(
    List<String> outputLines,
    String cwd,
    BuildStep step,
    bool trackPreviouslyLogged,
  ) async {
    final patterns = <LogType, RegExp>{
      LogType.erro: RegExp(r'(\s*error:?\s?)+', caseSensitive: false),
      LogType.warn: RegExp(r'(\s*warning:?\s?)+', caseSensitive: false),
      LogType.info: RegExp(r'(\s*info:?\s?)+', caseSensitive: false),
      LogType.note: RegExp(r'(\s*note:?\s?)+', caseSensitive: false),
    };

    var skipThisErrStack = false;
    var prevLogType = LogType.warn;

    final Box<BuildBox>? buildBox;
    if (trackPreviouslyLogged) {
      Hive
        ..init(p.join(cwd, '.rush'))
        ..registerAdapter(BuildBoxAdapter());
      buildBox = await Hive.openBox<BuildBox>('build');
    } else {
      buildBox = null;
    }

    for (var line in outputLines) {
      final MapEntry<LogType, RegExp>? type;
      if (patterns.values.any((el) => line.contains(el))) {
        type = patterns.entries.firstWhere((el) => line.contains(el.value));
      } else {
        type = null;
      }

      final List<String> previouslyLogged;
      if (trackPreviouslyLogged && buildBox != null) {
        previouslyLogged = buildBox.getAt(0)!.previouslyLogged;
        if (previouslyLogged.contains(line)) {
          skipThisErrStack = true;
          continue;
        }
      } else {
        previouslyLogged = [];
      }

      if (type != null) {
        var formattedLine = line.replaceFirst(
            type.value, line.startsWith(type.value) ? '' : ' ');

        if (formattedLine.startsWith(cwd)) {
          formattedLine = formattedLine.replaceFirst(p.join(cwd, 'src'), 'src');
        }

        step.log(type.key, formattedLine);
        prevLogType = type.key;
        skipThisErrStack = false;

        if (trackPreviouslyLogged && buildBox != null) {
          buildBox.updatePreviouslyLogged([...previouslyLogged, line]);
        }
      } else if (!skipThisErrStack) {
        if (line.startsWith(cwd)) {
          line = line.replaceFirst(p.join(cwd, 'src'), 'src');
        }
        step.log(prevLogType, ' ' * 5 + line, addPrefix: false);
      }
    }

    if (trackPreviouslyLogged) {
      await buildBox!.close();
    }
  }
}
