import 'dart:convert';
import 'dart:io';

import 'package:dart_console/dart_console.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/installer/installer.dart';
import 'package:rush_prompt/rush_prompt.dart';

Future<void> main(List<String> args) async {
  PrintArt();

  final installer = Installer();
  var rushDir = installer.getRushDir();

  if (rushDir != null) {
    Logger.log('An old version of Rush was found at: $rushDir\n');

    final shouldUpdate = BoolQuestion(
            id: 'up',
            question: 'Would you like to update it with the latest version?')
        .ask()[1];

    if (shouldUpdate) {
      final exePath =
          p.join(rushDir, 'bin', 'rush' + (Platform.isWindows ? '.exe' : ''));

      await installer.downloadBinaries(exePath);
      installer.printFooter(exePath, false);
    }

    installer.abort(1);
  }

  if (Platform.isWindows) {
    Logger.log(
        'Please select the directory in which you wish to install Rush...');
    await Future.delayed(Duration(seconds: 3));

    final picker = DirectoryPicker()..hidePinnedPlaces = true;

    rushDir = picker.getDirectory()?.path;

    if (rushDir == null) {
      Logger.log('Installation failed; no directory selected...',
          color: ConsoleColor.red);
      installer.abort(1);
    }
  } else {
    Logger.log(
        'Please enter the path to the directory where you wish to install Rush:');

    rushDir = stdin.readLineSync(encoding: Encoding.getByName('UTF-8')!);

    if (rushDir == null) {
      Logger.logErr('Invalid directory...', addSpace: true);
      installer.abort(1);
    } else if (!Directory(rushDir).existsSync()) {
      Logger.logErr('Directory $rushDir doesn\'t exist...', addSpace: true);
      installer.abort(1);
    }
  }

  final exePath;
  if (rushDir!.endsWith('/rush') || rushDir.endsWith('\\rush')) {
    exePath =
        p.join(rushDir, 'bin', 'rush' + (Platform.isWindows ? '.exe' : ''));
  } else {
    exePath = p.join(
        rushDir, 'rush', 'bin', 'rush' + (Platform.isWindows ? '.exe' : ''));
  }

  await installer.downloadBinaries(exePath);

  installer
    ..printFooter(exePath)
    ..abort(0);
}
