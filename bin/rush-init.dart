import 'dart:convert';
import 'dart:io' show Directory, Platform, stdin;

import 'package:args/args.dart';
import 'package:dart_console/dart_console.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/installer/installer.dart';
import 'package:rush_prompt/rush_prompt.dart';

Future<void> main(List<String> args) async {
  PrintArt();

  final parser = ArgParser()
    ..addFlag('force', abbr: 'f', defaultsTo: false, hide: true);
  final res = parser.parse(args);

  final installer = Installer(res['force']);
  var rushDir = installer.getRushDir();

  if (rushDir != null) {
    final exePath =
        p.join(rushDir, 'bin', 'rush' + (Platform.isWindows ? '.exe' : ''));

    Logger.log(
        'Rush is already installed on this computer, attempting to upgrade it...\n');
    Logger.log('Fetching data...\n');

    await installer.downloadFiles(exePath);

    installer
      ..printFooter(exePath, false)
      ..abort(1);
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

  Logger.log('\nFetching data...\n');
  await installer.downloadFiles(exePath);

  installer
    ..printFooter(exePath)
    ..abort(0);
}
