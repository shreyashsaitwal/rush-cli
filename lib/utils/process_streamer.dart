import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/commands/build/hive_adapters/build_box.dart';
import 'package:rush_prompt/rush_prompt.dart';

class ProcessResult {
  late final bool _success;
  final ErrWarnStore _errWarnStore = ErrWarnStore();

  ProcessResult._(this._success);

  bool get success => _success;
  ErrWarnStore get store => _errWarnStore;
}

class ProcessStreamer {
  /// Starts a process from given [args] and returns a stream of events emitted
  /// by that process.
  static Future<ProcessResult> stream(
    List<String> args,
    String cwd, {
    Directory? workingDirectory,
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

    final process = await Process.start(
      args[0],
      args.sublist(1),
      workingDirectory: workingDirectory?.path,
    );

    if (printNormalOutput) {
      await for (final chunk in process.stdout) {
        await _printChunkToTheConsole(chunk, cwd, step, trackPreviouslyLogged);
      }
    } else {
      // Drain the stdout stream otherwise it'd block the process till completion.
      // ignore: unawaited_futures
      process.stdout.drain();
    }

    await for (final chunk in process.stderr) {
      await _printChunkToTheConsole(chunk, cwd, step, trackPreviouslyLogged);
    }

    return ProcessResult._(await process.exitCode == 0);
  }

  /// Prints [chunk] to the console with appropriate [LogType].
  static Future<void> _printChunkToTheConsole(
    List<int> chunk,
    String cwd,
    BuildStep step,
    bool trackPreviouslyLogged,
  ) async {
    final logTypePatterns = <LogType, RegExp>{
      LogType.erro: RegExp(r'\s*(error:){1}\s?', caseSensitive: false),
      LogType.warn: RegExp(r'\s*(warn(ing)?:){1}\s?', caseSensitive: false),
      LogType.info: RegExp(r'\s*(info:){1}\s?', caseSensitive: false),
      LogType.note: RegExp(r'\s*(note:){1}\s?', caseSensitive: false),
    };

    // These patterns are either useless or don't make sense in Rush's context.
    // For example, the error and warning count printed by javac is not necessary
    // to print as Rush itself keeps track of them.
    final excludePatterns = [
      RegExp(r'The\sfollowing\soptions\swere\snot\srecognized'),
      RegExp(r'\d+\s*warnings?\s?'),
      RegExp(r'\d+\s*errors?\s?'),
      RegExp(r'.*Recompile\swith.*for\sdetails', dotAll: true),
    ];

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

    final outputLines = LineSplitter.split(String.fromCharCodes(chunk))
        .where((line) => line.trim().isNotEmpty)
        .where((line) =>
            !excludePatterns.any((pattern) => pattern.hasMatch(line)));

    for (var line in outputLines) {
      final MapEntry<LogType, RegExp>? type;
      if (logTypePatterns.values.any((el) => line.contains(el))) {
        type =
            logTypePatterns.entries.firstWhere((el) => line.contains(el.value));
      } else {
        type = null;
      }

      final List<String> previouslyLogged;
      if (trackPreviouslyLogged) {
        previouslyLogged = buildBox!.getAt(0)!.previouslyLogged;
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
