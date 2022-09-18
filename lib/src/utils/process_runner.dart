import 'dart:convert';
import 'dart:io' show Process, ProcessException;

import 'package:get_it/get_it.dart';
import 'package:rush_cli/src/services/file_service.dart';
import 'package:rush_cli/src/services/logger.dart';

class ProcessRunner {
  final _fs = GetIt.I<FileService>();
  final _lgr = GetIt.I<Logger>();

  Future<void> runExecutable(String exe, List<String> args) async {
    final Process process;
    try {
      process = await Process.start(exe, args, environment: {
        'RUSH_HOME': _fs.rushHomeDir.path,
        'RUSH_PROJECT_ROOT': _fs.cwd,
      });
    } catch (e) {
      rethrow;
    }

    process
      ..stdout.transform(utf8.decoder).listen((chunk) {
        _lgr.parseAndLog(chunk);
      })
      ..stderr.transform(utf8.decoder).listen((chunk) {
        _lgr.parseAndLog(chunk);
      });

    if (await process.exitCode != 0) {
      throw ProcessException(exe, args);
    }
  }
}
