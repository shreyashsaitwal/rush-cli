import 'dart:io' show Platform, stdin, stdout, exit;

import 'package:dart_console/dart_console.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:process_run/which.dart';
import 'package:rush_cli/helpers/app_data_dir.dart';
import 'package:rush_cli/installer/model/bin_data.dart';
import 'package:rush_prompt/rush_prompt.dart';

class Installer {
  final _dataDir = RushDataDir.dataDir()!;

  Future<void> downloadBinaries(String exePath) async {
    const endpoint = 'https://get-rush.herokuapp.com';

    Logger.log('\nFetching data...\n');

    final dio = Dio();
    final response = await dio.get(endpoint + '/api/v1/dl/' + _getOs());

    final json = response.data as List;
    final binData = <BinData>[];

    var totalSize = 0;

    json.forEach((el) {
      final data = BinData.fromJson(el);
      totalSize += data.size;
      binData.add(data);
    });

    final pb = ProgressBar('Downloading binaries (${totalSize ~/ 1e+6} MB)...');
    pb.totalProgress = binData.length;
    pb.update(0);

    var count = 0;
    for (final data in binData) {
      await _download(data, exePath);
      count++;
      pb.update(count);
    }
  }

  Future<void> _download(BinData data, String exePath) async {
    final savePath;
    if (data.path.startsWith('exe')) {
      savePath = exePath;
    } else {
      savePath = p.join(_dataDir, data.path);
    }
    
    await Dio().download(data.download, savePath);
  }

  void printFooter(String exePath, [bool printAdditional = true]) {
    final console = Console();

    final rushDir = p.dirname(p.dirname(exePath));

    console
      ..writeLine()
      ..setForegroundColor(ConsoleColor.brightGreen)
      ..write('Success! ')
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..write('Installed Rush in directory: ')
      ..setForegroundColor(ConsoleColor.cyan)
      ..writeLine(rushDir)
      ..writeLine()
      ..setForegroundColor(ConsoleColor.brightWhite);

    if (!printAdditional) {
      return;
    }

    if (Platform.isWindows) {
      console
        ..writeLine(
            'Now, update your PATH environment variable by adding the following path to it:')
        ..setForegroundColor(ConsoleColor.cyan)
        ..writeLine(p.join(rushDir, 'bin'));
    } else {
      console
        ..writeLine('Now,')
        ..writeLine(
            '  - run the following command to give execution permission to the Rush executable:')
        ..setForegroundColor(ConsoleColor.cyan)
        ..writeLine(' ' * 4 + 'chmod +x ' + p.join(rushDir, 'bin', 'rush'))
        ..setForegroundColor(ConsoleColor.brightWhite)
        ..writeLine(
            '  - and then, update your PATH environment variable to include the Rush executable like so:')
        ..setForegroundColor(ConsoleColor.cyan)
        ..writeLine(
            ' ' * 4 + 'export PATH="\$PATH:' + p.join(rushDir, 'bin') + '"');
    }

    console
      ..resetColorAttributes()
      ..writeLine()
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..write('For more info, visit here: ')
      ..setForegroundColor(ConsoleColor.blue)
      ..writeLine(
          'https://github.com/ShreyashSaitwal/rush-cli/wiki/Installation')
      ..resetColorAttributes();
  }

  String _getOs() {
    final os = Platform.operatingSystem;

    switch (os) {
      case 'windows':
        return 'win';
      case 'macos':
        return 'mac';
      default:
        return 'linux';
    }
  }

  String? getRushDir() {
    final whichRush = whichSync('rush') ?? '';

    if (whichRush != '') {
      return p.dirname(p.dirname(whichRush));
    }

    return null;
  }

  void abort(int exitCode) {
    if (Platform.isWindows) {
      stdout.write('\nPress any key to continue... ');
      stdin.readLineSync();
    }
    exit(exitCode);
  }
}
