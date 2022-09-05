import 'package:args/command_runner.dart';

abstract class RushCommand extends Command<int> {
  // TODO: Pretty print help output
}

class RushCommandRunner extends CommandRunner<int> {
  RushCommandRunner()
      : super('rush',
            'A new and improved way of building App Inventor 2 extensions.');

  // TODO: Pretty print usage output
}
