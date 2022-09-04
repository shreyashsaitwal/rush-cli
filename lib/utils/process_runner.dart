import 'dart:convert';
import 'dart:io' show Process, ProcessException;

import 'package:get_it/get_it.dart';
import 'package:rush_cli/services/file_service.dart';

// TODO: Not yet complete
class ProcessRunner {
  final _fs = GetIt.I<FileService>();

  Future<void> runExecutable(String exe, List<String> args) async {
    final Process process;
    try {
      process = await Process.start(exe, args, environment: {
        'RUSH_HOME': _fs.rushHomeDir.path,
        'RUSH_PROJECT_ROOT': _fs.cwd,
      });
    } catch (e) {
      // TODO: Is this any different than not try catching at all?
      rethrow;
    }

    process
      ..stdout.transform(utf8.decoder).listen((data) {
        print(data.trimRight());
      })
      ..stderr.transform(utf8.decoder).listen((data) {
        print(data.trimRight());
      });

    if (await process.exitCode != 0) {
      throw ProcessException(exe, args);
    }
  }
}
