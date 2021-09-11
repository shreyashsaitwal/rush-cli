import 'package:rush_cli/commands/deps/sync.dart';
import 'package:rush_cli/commands/deps/tree.dart';
import 'package:rush_cli/commands/rush_command.dart';
import 'package:rush_cli/services/file_service.dart';

class DepsCommand extends RushCommand {
  final FileService _fs;

  DepsCommand(this._fs) {
    addSubcommand(DepsTreeCommand(_fs));
    addSubcommand(DepsSyncCommand(_fs));
  }

  @override
  String get description => 'Work with project dependencies.';

  @override
  String get name => 'deps';
}
