import 'dart:io';

import 'package:rush_cli/commands/build_command/build_command.dart';
import 'package:rush_cli/commands/create_command/create_command.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2 && args.contains('create')) {
    await CreateCommand(Directory.current.path).run();
  } else if (args.length < 3 && args.contains('build') && (args.contains('-r') || args.contains('--release'))) {
    await BuildCommand(Directory.current.path, true).run();
  } else if (args.length < 2 && args.contains('build')) {
    await BuildCommand(Directory.current.path, false).run();
  } else {
    exit(2);
  }
}
