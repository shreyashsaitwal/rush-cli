import './info.dart';
import './sync.dart';
import '../../commands/rush_command.dart';

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
