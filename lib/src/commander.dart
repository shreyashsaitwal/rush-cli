import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:rush/src/commands/create_command.dart';

class Commander extends CommandRunner {
  Commander() : super('rush', 'Placeholder description for the meantime.') {
    final List<Command> commands = [CreateCommand(Directory.current)];

    for (final command in commands) {
      addCommand(command);
    }
  }
}
