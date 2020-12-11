import 'dart:io';

import 'package:rush_cli/commands/new_command/new_command.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2 && args.contains('new')) {
    await NewCommand(Directory.current.path).run();
  } else {
    exit(2);
  }
}

