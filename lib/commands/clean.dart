import 'dart:io' show Directory, File, exit;
import 'dart:math';

import 'package:get_it/get_it.dart';
import 'package:interact/interact.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/commands/rush_command.dart';
import 'package:rush_cli/services/file_service.dart';
import 'package:tint/tint.dart';

import '../services/logger.dart';

class CleanCommand extends RushCommand {
  final _fs = GetIt.I<FileService>();
  final _logger = GetIt.I<Logger>();

  @override
  String get description => 'Deletes old build files and caches.';

  @override
  String get name => 'clean';

  @override
  Future<int> run() async {
    if (!await _isRushProject()) {
      _logger.error('Not a Rush project.');
      return 1;
    }

    final spinner = Spinner(
        icon: '\n✔'.green(),
        rightPrompt: (done) => done
            ? '${'Success!'.green()} Deleted build files and caches'
            : 'Cleaning...').interact();
    for (final file in _fs.dotRushDir.listSync()) {
      file.deleteSync(recursive: true);
    }

    await Future.delayed(Duration(milliseconds: Random().nextInt(2000)));
    spinner.done();
    return 0;
  }

  Future<bool> _isRushProject() async {
    final rushYaml = await () async {
      final yml = File(p.join(_fs.cwd, 'rush.yml'));
      if (await yml.exists()) {
        return yml;
      } else {
        return File(p.join(_fs.cwd, 'rush.yaml'));
      }
    }();

    final androidManifest =
        File(p.join(_fs.srcDir.path, 'AndroidManifest.xml'));
    final dotRushDir = Directory(p.join(_fs.cwd, '.rush'));

    return await rushYaml.exists() &&
        await _fs.srcDir.exists() &&
        await androidManifest.exists() &&
        await dotRushDir.exists();
  }
}
