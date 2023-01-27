import 'dart:io' show Process, ProcessException, systemEncoding;

import 'package:get_it/get_it.dart';
import 'package:rush_cli/src/services/file_service.dart';
import 'package:rush_cli/src/services/logger.dart';
import 'package:rush_cli/src/services/lib_service.dart';
import 'package:rush_cli/src/utils/constants.dart';

class ProcessRunner {
  final _fs = GetIt.I<FileService>();
  final _lgr = GetIt.I<Logger>();
  final _libService = GetIt.I<LibService>();

  Future<void> runExecutable(String exe, List<String> args) async {
    final Process process;
    final providedDeps = await _libService.providedDependencies();
    try {
      process = await Process.start(exe, args, environment: {
        // These variables are used by the annotation processor
        'RUSH_PROJECT_ROOT': _fs.cwd,
        'RUSH_ANNOTATIONS_JAR': providedDeps
            .singleWhere((el) =>
                el.coordinate ==
                'io.github.shreyashsaitwal.rush:annotations:$ai2AnnotationVersion')
            .artifactFile,
        'RUSH_RUNTIME_JAR': providedDeps
            .singleWhere((el) =>
                el.coordinate ==
                'io.github.shreyashsaitwal.rush:runtime:$ai2RuntimeVersion')
            .artifactFile,
      });
    } catch (e) {
      if (e.toString().contains('The system cannot find the file specified')) {
        _lgr.err(
            'Could not run `$exe`. Make sure it is installed and in PATH.');
      }
      rethrow;
    }

    process
      ..stdout.transform(systemEncoding.decoder).listen((chunk) {
        _lgr.parseAndLog(chunk);
      })
      ..stderr.transform(systemEncoding.decoder).listen((chunk) {
        _lgr.parseAndLog(chunk);
      });

    if (await process.exitCode != 0) {
      throw ProcessException(exe, args);
    }
  }
}
