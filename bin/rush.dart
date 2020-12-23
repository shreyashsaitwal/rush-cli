import 'dart:io';

import 'package:rush_cli/commands/build_command/build_command.dart';
import 'package:rush_cli/commands/new_command/new_command.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2 && args.contains('new')) {
    await NewCommand(Directory.current.path).run();
  } else if (args.length < 2 && args.contains('build')) {
    await BuildCommand(Directory.current.path, 'io.shreyash.phase').run();
  } else {
    exit(2);
  }
}

