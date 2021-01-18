import 'dart:io';

import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

import 'package:rush_cli/commands/build_command/build_command.dart';
import 'package:rush_cli/commands/new_command/new_command.dart';
import 'package:rush_cli/mixins/app_data_dir_mixin.dart';

Future<void> main(List<String> args) async {
  await Hive.init(p.join(AppDataMixin.dataStorageDir(), 'bin'));

  if (args.length < 2 && args.contains('new')) {
    await NewCommand(Directory.current.path).run();
  } else if (args.length < 2 && args.contains('build')) {
    await BuildCommand(Directory.current.path, 'io.rush', true).run();
  } else {
    exit(2);
  }
}

