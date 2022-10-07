import 'package:args/command_runner.dart';

import 'package:rush_cli/src/commands/deps/tree.dart';
import 'package:rush_cli/src/commands/deps/sync.dart';

class DepsCommand extends Command<int> {
  DepsCommand() {
    addSubcommand(TreeSubCommand());
    addSubcommand(SyncSubCommand());
  }

  @override
  String get description => 'Work with project dependencies.';

  @override
  String get name => 'deps';
}
