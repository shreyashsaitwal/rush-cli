import 'package:rush_cli/commands/deps/sync.dart';
import 'package:rush_cli/commands/rush_command.dart';
import '../../services/file_service.dart';

class DepsCommand extends RushCommand {
  final FileService _fs;

  DepsCommand(this._fs) {
    addSubcommand(SyncSubCommand(_fs));
  }

  @override
  String get description => 'Work with project dependencies.';

  @override
  String get name => 'deps';
}
