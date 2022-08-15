import 'package:rush_cli/commands/deps/info.dart';
import 'package:rush_cli/commands/deps/sync.dart';
import 'package:rush_cli/commands/rush_command.dart';

class DepsCommand extends RushCommand {
  DepsCommand() {
    addSubcommand(InfoSubCommand());
    addSubcommand(SyncSubCommand());
  }

  @override
  String get description => 'Work with project dependencies.';

  @override
  String get name => 'deps';
}
