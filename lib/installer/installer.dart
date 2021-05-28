import 'dart:io' show Directory, File, Platform, Process, exit, stdin, stdout;

import 'package:dart_console/dart_console.dart';
import 'package:dio/dio.dart';
import 'package:github/github.dart'
    show Authentication, GitHub, GitHubFile, Release, RepositorySlug;
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:process_run/which.dart';
import 'package:rush_cli/helpers/app_data_dir.dart';
import 'package:rush_cli/env.dart';
import 'package:rush_prompt/rush_prompt.dart';

class Installer {
  final bool _force;
  final _dataDir = RushDataDir.dataDir()!;

  var _totalSize = 0;
  int get totatSize => _totalSize;

  Installer(this._force) {
    final boxDir = Directory(p.join(_dataDir, '.installer'));
    if (_force) {
      boxDir.deleteSync(recursive: true);
    }

    Hive.init(boxDir.path);
  }

  Future<List<GitHubFile>> fetchRequiredFiles(String path) async {
    final gh = GitHub(auth: Authentication.withToken(GH_PAT));
    final contents = <GitHubFile>[];

    final res = await gh.repositories
        .getContents(RepositorySlug('shreyashsaitwal', 'rush-pack'), path);

    final box = await Hive.openBox('init.data');

    for (final entity in res.tree!) {
      final nonOsPaths = _getNonOsPaths();

      if (entity.type == 'dir') {
        contents.addAll(await fetchRequiredFiles(entity.path!));
      } else if (!nonOsPaths.contains(entity.path)) {
        final boxedEntity = await box.get(entity.name) ??
            <String, String>{'sha': '', 'path': ''};

        final boxedSha = boxedEntity['sha'] ?? '';
        final boxedPath = boxedEntity['path'] ?? '';

        if (boxedSha != entity.sha || !File(boxedPath).existsSync()) {
          contents.add(entity);
          _totalSize += entity.size!;
        }
      }
    }

    return contents;
  }

  Future<void> downloadAllFiles(String binDir, List<GitHubFile> files,
      {ProgressBar? pb, bool isUpgrade = false}) async {
    final box = await Hive.openBox('init.data');

    for (final file in files) {
      await _download(file, binDir, box, isUpgrade);
      pb?.increment();
    }
  }

  Future<Release> getLatestRelease() async {
    final gh = GitHub(auth: Authentication.withToken(GH_PAT));

    final release = await gh.repositories
        .getLatestRelease(RepositorySlug('shreyashsaitwal', 'rush-pack'));

    return release;
  }

  Future<void> _download(
      GitHubFile file, String binDir, Box box, bool isUpgrade) async {
    final savePath;

    if (file.path!.startsWith('exe')) {
      if (isUpgrade && RegExp(r'rush(.exe)?').hasMatch(file.name!)) {
        savePath = p.join(binDir, file.name! + '.new');
      } else {
        savePath = p.join(binDir, file.name);
      }
    } else {
      savePath = p.join(_dataDir, file.path);
    }

    try {
      await Dio().download(file.downloadUrl!, savePath);
    } catch (e) {
      Logger.logErr(e.toString(), addPrefix: false);
      abort(1);
    }

    if (!Platform.isWindows && file.path!.startsWith('exe')) {
      Process.runSync('chmod', ['+x', savePath]);
    }

    // Once the file is downloaded add it's sha and path to the box so next
    // time it doesn't get downloaded if it's not updated or deleted.
    await box.put(file.name, {'sha': file.sha!, 'path': savePath});
  }

  List<String> _getNonOsPaths() {
    final os = Platform.operatingSystem;
    final res = <String>[
      'exe/win/rush.exe',
      'exe/mac/rush',
      'exe/linux/rush',
    ];

    switch (os.toLowerCase()) {
      case 'windows':
        res.removeAt(0);
        break;

      case 'macos':
        res.removeAt(1);
        break;

      case 'linux':
        res.removeAt(2);
        break;
    }

    return res;
  }

  void printFooter(String exePath, [bool printAdditional = true]) {
    final console = Console();

    final rushDir = Directory(p.dirname(p.dirname(exePath))).path;

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
        ..writeLine(
            'Now, update your PATH environment variable to include the Rush executable like so:')
        ..setForegroundColor(ConsoleColor.cyan)
        ..writeLine(
            ' ' * 2 + 'export PATH="\$PATH:' + p.join(rushDir, 'bin') + '"');
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
