import 'dart:convert';
import 'dart:io' show Process, ProcessException, systemEncoding;

import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:rush/src/services/file_service.dart';
import 'package:rush/src/services/logger.dart';
import 'package:rush/src/services/lib_service.dart';
import 'package:rush/src/services/ai2_runtime.dart';
import 'package:rush/src/version.dart';
import 'package:tint/tint.dart';

class ProcessRunner {
  final _fs = GetIt.I<FileService>();
  final _lgr = GetIt.I<Logger>();
  final _libService = GetIt.I<LibService>();

  Future<void> runExecutable(String exe, List<String> args,
      {RegExp? debugLines}) async {
    final Process process;
    final runtime = await Ai2Runtime.load();
    try {
      process = await Process.start(exe, args, environment: {
        // These variables are used by the annotation processor
        'RUSH_PROJECT_ROOT': _fs.cwd,
        'RUSH_ANNOTATIONS_JAR': _libService.annotationsJar,
        'RUSH_RUNTIME_JAR': runtime.runtimeJar,
        'RUSH_VERSION': packageVersion,
      });
    } on ProcessException catch (e) {
      _lgr.err('Could not run `$exe`: ${e.message}');
      if (p.basenameWithoutExtension(exe).startsWith('java')) {
        _lgr.log('Rush needs JDK 17 or newer, on PATH or in JAVA_HOME',
            'help  '.green());
      }
      rethrow;
    }

    for (final output in [process.stdout, process.stderr]) {
      output
          .transform(systemEncoding.decoder)
          .transform(const LineSplitter())
          .listen((line) => _lgr.parseAndLog(line, debugLines: debugLines));
    }

    if (await process.exitCode != 0) {
      throw ProcessException(exe, args);
    }
  }
}
