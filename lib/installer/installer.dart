import 'dart:convert';
import 'dart:io';

import 'package:dart_console/dart_console.dart';
import 'package:dio/dio.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:path/path.dart' as p;
import 'package:process_run/shell.dart';
import 'package:process_runner/process_runner.dart';
import 'package:rush_cli/helpers/app_data_dir.dart';
import 'package:rush_cli/installer/model/download_data.dart';
import 'package:rush_prompt/rush_prompt.dart';

class Installer {
  final _dataDir = RushDataDir.dataDir()!;

  Future<void> install() async {
    if (!_isJavaInstalled()) {
      Logger.log('JDK not found...', color: ConsoleColor.red);
      Logger.log('Rush needs Java to compile your extension.\n'
          'Please download and install JDK version 1.8 or above before installing Rush.');
      _abort(1);
    }

    if (!_isRushInstalled()) {
      if (Platform.isWindows) {
        Logger.log(
            'Please select the directory in which you wish to install Rush...');
        await Future.delayed(Duration(seconds: 3));

        final picker = DirectoryPicker()..hidePinnedPlaces = true;
        final rushDir = picker.getDirectory();

        if (rushDir == null) {
          Logger.log('Installation failed; no directory selected...',
              color: ConsoleColor.red);
          _abort(1);
        }

        await _downloadRush(rushDir!.path);
        _printFooter(rushDir.path);
      } else {
        Logger.log(
            'Please enter the path to the directory you wish to install Rush:');
        final rushDirPath =
            stdin.readLineSync(encoding: Encoding.getByName('UTF-8')!);

        if (rushDirPath == null || rushDirPath == '') {
          Logger.logErr('Invalid directory...', addSpace: true);
          _abort(1);
        } else if (!Directory(rushDirPath).existsSync()) {
          Logger.logErr('Directory $rushDirPath doesn\'t exist...',
              addSpace: true);
          _abort(1);
        }

        await _downloadRush(rushDirPath!);
        await _exportPathUnix(rushDirPath);

        _printFooter(rushDirPath);
      }
    } else {
      final rushDir = p.dirname(p.dirname(whichSync('rush')!));
      Logger.log('An old version of Rush was found at: $rushDir\n');
      final shouldUpdate = BoolQuestion(
              id: 'up',
              question: 'Would you like to update it with the latest version?')
          .ask()[1];

      if (shouldUpdate) {
        _deleteOldRush(rushDir);
        await _downloadRush(rushDir);
      }

      if (!Platform.isWindows) {
        await _exportPathUnix(p.join(rushDir, 'bin'));
      }

      _printFooter(rushDir);
    }
  }

  void _deleteOldRush(String rushDir) {
    final binDir = Directory(p.join(rushDir, 'bin'));
    final toolsDir = Directory(p.join(rushDir, 'tools'));
    final devDepsDir = Directory(p.join(rushDir, 'dev-deps'));

    try {
      binDir.deleteSync(recursive: true);
      toolsDir.deleteSync(recursive: true);
      devDepsDir.deleteSync(recursive: true);
    } catch (e) {
      Logger.logErr('Unable to delete old Rush files...', addSpace: true);
      Logger.logErr(e.toString(), addPrefix: false);
      _abort(1);
    }
  }

  Future<void> _downloadRush(String rushDir) async {
    final rushBin;
    if (p.basename(rushDir) == 'rush') {
      rushBin = Directory(p.join(rushDir, 'bin'));
    } else {
      rushBin = Directory(p.join(rushDir, 'rush', 'bin'));
    }

    final devDepsDir = Directory(p.join(_dataDir, 'dev-deps'));
    final processorDir = Directory(p.join(_dataDir, 'tools', 'processor'));

    final jetifierBinDir =
        Directory(p.join(_dataDir, 'tools', 'jetifier-standalone', 'bin'));
    final jetifierLibDir =
        Directory(p.join(_dataDir, 'tools', 'jetifier-standalone', 'lib'));

    final otherDir = Directory(p.join(_dataDir, 'tools', 'other'));

    try {
      rushBin.createSync(recursive: true);
      devDepsDir.createSync(recursive: true);
      processorDir.createSync(recursive: true);
      jetifierBinDir.createSync(recursive: true);
      jetifierLibDir.createSync(recursive: true);
      otherDir.createSync(recursive: true);
    } catch (e) {
      Logger.logErr(e.toString());
    }

    final downloadData = await _fetch();
    final futures = <Future>[];

    downloadData.data.forEach((el) async {
      if (el.name == 'rush' || el.name == 'rush.exe') {
        futures.add(_download(rushBin, el.url, el.name));
      } else if (el.path.startsWith('dev-deps')) {
        futures.add(_download(devDepsDir, el.url, el.name));
      } else if (el.path.startsWith('tools/processor')) {
        futures.add(_download(processorDir, el.url, el.name));
      } else if (el.path.startsWith('tools/jetifier-standalone/bin')) {
        futures.add(_download(jetifierBinDir, el.url, el.name));
      } else if (el.path.startsWith('tools/jetifier-standalone/lib')) {
        futures.add(_download(jetifierLibDir, el.url, el.name));
      } else {
        futures.add(_download(otherDir, el.url, el.name));
      }
    });

    await Future.wait(futures);
  }

  Future<void> _download(Directory dir, String url, String name) async {
    Logger.log('Downloading $name...');
    await Dio().download(url, p.join(dir.path, name), deleteOnError: true);
  }

  Future<DownloadData> _fetch() async {
    const endpoint = 'https://rush-api.shreyashsaitwal.repl.co/download';
    final dio = Dio();

    try {
      final response = await dio.get(endpoint);
      return DownloadData.fromJson(response.data);
    } catch (e) {
      Logger.logErr(e.toString());
      exit(1);
    }
  }

  Future<void> _exportPathUnix(String binDir) async {
    await ProcessRunner().runProcess(['export', 'PATH="\$PATH:$binDir"']);
  }

  void _printFooter(String rushInstPath) {
    final console = Console()
      ..writeLine()
      ..setForegroundColor(ConsoleColor.brightGreen)
      ..write('Success! ')
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..write('Installed Rush in directory: ')
      ..setForegroundColor(ConsoleColor.cyan)
      ..writeLine(rushInstPath)
      ..writeLine()
      ..resetColorAttributes();

    if (Platform.isWindows) {
      console
        ..setForegroundColor(ConsoleColor.brightWhite)
        ..writeLine(
            'Now, update your PATH environment variable for the current user by adding the following path to it:')
        ..setForegroundColor(ConsoleColor.cyan)
        ..writeLine(p.join(rushInstPath, 'rush', 'bin'))
        ..resetColorAttributes()
        ..writeLine()
        ..setForegroundColor(ConsoleColor.brightWhite)
        ..write('For more info, visit here: ')
        ..setForegroundColor(ConsoleColor.blue)
        ..writeLine(
            'https://github.com/ShreyashSaitwal/rush-cli/wiki/Installation#windows-64-bit')
        ..resetColorAttributes();
    } else {
      console
        ..setForegroundColor(ConsoleColor.brightWhite)
        ..writeLine(
            'You\'re now all set up start building awesome extensions with Rush!');
    }

    _abort(0);
  }

  bool _isJavaInstalled() {
    final whichJava = whichSync('java');
    return whichJava == null ? false : true;
  }

  bool _isRushInstalled() {
    final whichRush = whichSync('rush');
    return whichRush == null ? false : true;
  }

  void _abort(int exitCode) {
    stdout.write('\nPress any key to continue... ');
    stdin.readLineSync();
    exit(exitCode);
  }
}
