import 'dart:convert';
import 'dart:io' show Process, ProcessException, systemEncoding;

import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:rush/src/services/logger.dart';
import 'package:tint/tint.dart';

class ProcessRunner {
  final _lgr = GetIt.I<Logger>();

  Future<void> runExecutable(String exe, List<String> args,
      {RegExp? debugLines, bool debugStdout = false}) async {
    final Process process;
    try {
      process = await Process.start(exe, args);
    } on ProcessException catch (e) {
      _lgr.err('Could not run `$exe`: ${e.message}');
      if (p.basenameWithoutExtension(exe).startsWith('java')) {
        _lgr.log('Rush needs JDK 17 or newer, on PATH or in JAVA_HOME',
            'help  '.green());
      }
      rethrow;
    }

    _lines(process.stdout).listen(debugStdout
        ? _lgr.dbg
        : (line) => _lgr.parseAndLog(line, debugLines: debugLines));
    _lines(process.stderr)
        .listen((line) => _lgr.parseAndLog(line, debugLines: debugLines));

    if (await process.exitCode != 0) {
      throw ProcessException(exe, args);
    }
  }

  Stream<String> _lines(Stream<List<int>> output) =>
      output.transform(systemEncoding.decoder).transform(const LineSplitter());
}
