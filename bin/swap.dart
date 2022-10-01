import 'dart:io';

import 'package:args/args.dart';

/// Swaps the old rush.exe with the new one on Windows.
Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('old-exe')
    ..addOption('message');
  final res = parser.parse(args);

  final oldExe = File(res['old-exe'] as String);
  oldExe.deleteSync();

  final newExe = File('${oldExe.path}.new');
  newExe.renameSync(oldExe.path);

  print(res['message'] as String);
}
