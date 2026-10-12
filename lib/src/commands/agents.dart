import 'package:args/command_runner.dart';
import 'package:get_it/get_it.dart';

import 'package:rush/src/agents/agent_files.dart';
import 'package:rush/src/services/file_service.dart';
import 'package:rush/src/services/logger.dart';

class AgentsCommand extends Command<int> {
  final _fs = GetIt.I<FileService>();
  final _lgr = GetIt.I<Logger>();

  @override
  String get description =>
      'Adds or updates the instructions AI coding agents follow in this project.';

  @override
  String get name => 'agents';

  @override
  Future<int> run() async {
    if (!await _fs.configFile.exists()) {
      _lgr.err('No rush.yml found in ${_fs.cwd}. Run this command inside a '
          'Rush project.');
      return 1;
    }
    for (final path in await writeAgentFiles(_fs.cwd)) {
      _lgr.info('Wrote $path');
    }
    return 0;
  }
}
