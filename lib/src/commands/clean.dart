import 'package:args/command_runner.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:tint/tint.dart';

import 'package:rush/src/services/file_service.dart';
import 'package:rush/src/services/logger.dart';
import 'package:rush/src/utils/file_extension.dart';
import 'package:rush/src/utils/progress.dart';

class CleanCommand extends Command<int> {
  final _fs = GetIt.I<FileService>();
  final _lgr = GetIt.I<Logger>();

  @override
  String get description => 'Deletes old build files and caches.';

  @override
  String get name => 'clean';

  @override
  Future<int> run() async {
    if (!await _isRushProject()) {
      _lgr.err('Not a Rush project.');
      return 1;
    }

    final progress = Progress(
        running: 'Cleaning...',
        done: '${'Success!'.green()} Deleted build files and caches');
    if (await _fs.dotRushDir.exists()) {
      for (final file in _fs.dotRushDir.listSync()) {
        await file.delete(recursive: true);
      }
    }

    progress.finish();
    return 0;
  }

  Future<bool> _isRushProject() async {
    final config = _fs.configFile;
    final androidManifest =
        p.join(_fs.srcDir.path, 'AndroidManifest.xml').asFile();
    return await config.exists() &&
        await _fs.srcDir.exists() &&
        await androidManifest.exists();
  }
}
