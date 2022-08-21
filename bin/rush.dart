import 'dart:io' show exit;

import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/commands/build/build.dart';
import 'package:rush_cli/commands/clean.dart';
import 'package:rush_cli/commands/create.dart';
import 'package:rush_cli/commands/deps/deps.dart';
import 'package:rush_cli/commands/rush_command.dart';
import 'package:rush_cli/services/libs_service.dart';
import 'package:rush_cli/services/service_locator.dart';
import 'package:rush_cli/version.dart';
import 'package:tint/tint.dart';

Future<void> main(List<String> args) async {
  _printArt();

  final commandRunner = RushCommandRunner();
  commandRunner.argParser.addFlag('version',
      abbr: 'v',
      negatable: false,
      help: 'Prints the version info of the current installation of Rush.',
      callback: (val) {
    if (val) {
      _printVersion();
    }
  });

  setupServiceLocator(p.current);
  await GetIt.I.isReady<LibService>();
  
  commandRunner
    ..addCommand(CreateCommand())
    ..addCommand(BuildCommand())
    // TODO: Fix these two
    // ..addCommand(MigrateCommand())
    // ..addCommand(UpgradeCommand())
    ..addCommand(CleanCommand())
    ..addCommand(DepsCommand());

  try {
    await commandRunner.run(args);
  } catch (e, s) {
    print(s);
    rethrow;
  }
}

void _printVersion() {
  print('Version: ${rushVersion.toString().cyan()}');
  print('Built on: ${rushBuiltOn.toString().cyan()}');
  exit(0);
}

void _printArt() {
  const art = r'''
                    __
   _______  _______/ /_
  / ___/ / / / ___/ __ \
 / /  / /_/ (__  / / / /
/_/   \__,_/____/_/ /_/
''';

  print(art.blue());
}
