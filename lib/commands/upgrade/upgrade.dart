import 'dart:io'
    show Directory, File, Platform, Process, ProcessStartMode, exit;

import 'package:args/command_runner.dart';
import 'package:dart_console/dart_console.dart';
import 'package:dio/dio.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:process_runner/process_runner.dart';
import 'package:rush_cli/commands/upgrade/models/repo_content.dart';
import 'package:rush_cli/commands/upgrade/models/gh_release.dart';
import 'package:rush_cli/version.dart';
import 'package:rush_prompt/rush_prompt.dart';

class UpgradeCommand extends Command<void> {
  final String _dataDir;
  static const String _endpt = 'https://rush-api.shreyashsaitwal.repl.co';

  UpgradeCommand(this._dataDir) {
    argParser
      ..addFlag('force',
          abbr: 'f',
          help:
              'Forcefully upgrades Rush to the latest version. This downloads '
              'and replaces even the unchanged files.',
          defaultsTo: false)
      ..addFlag('safe', abbr: 's', hide: true, defaultsTo: false);

    final dir = Directory(p.join(_dataDir, '.installer'))
      ..createSync(recursive: true);
    Hive.init(dir.path);
  }

  @override
  String get description => 'Upgrades Rush to the latest available version.';

  @override
  String get name => 'upgrade';

  @override
  void printUsage() {
    PrintArt();
    Console()
      ..setForegroundColor(ConsoleColor.cyan)
      ..write(' upgrade ')
      ..resetColorAttributes()
      ..writeLine(description)
      ..writeLine()
      ..write(' Usage: ')
      ..setForegroundColor(ConsoleColor.brightBlue)
      ..write('rush ')
      ..setForegroundColor(ConsoleColor.cyan)
      ..writeLine('upgrade')
      ..resetColorAttributes()
      ..writeLine()
      ..writeLine(' Available flags:')
      ..setForegroundColor(ConsoleColor.yellow)
      ..write('   -f, --force')
      ..resetColorAttributes()
      ..writeLine('  ' +
          'Forcefully upgrades Rush to the latest version. This downloads and '
              'replaces even the unchanged files.')
      ..resetColorAttributes();
  }

  @override
  Future<void> run() async {
    final isForce = argResults?['force'] as bool;
    final initDataBox = await Hive.openBox('data.init');

    Logger.log(LogType.info, 'Fetching data...');
    final allContent = await _fetchAllContent(initDataBox);
    final reqContent = await _reqContents(initDataBox, allContent, isForce);

    final releaseInfo = await _fetchLatestRelease();

    if (releaseInfo.name == 'v$rushVersion' && !isForce) {
      Logger.log(LogType.warn,
          'You already have the latest version of Rush ($rushVersion) installed.');
      Logger.log(LogType.note,
          'To perform a force upgrade, run `rush upgrade --force`');
      exit(0);
    }

    final binDir = p.dirname(Platform.resolvedExecutable);

    Logger.log(
        LogType.info, 'Starting download... [${reqContent.length} MB]\n');
    final ProgressBar pb = ProgressBar(reqContent.length);

    for (final el in reqContent) {
      final savePath = () {
        if (el.path!.startsWith('exe')) {
          return p.join(binDir, el.name! + '.new');
        }
        return p.join(_dataDir, el.path);
      }();

      await Dio().download(el.downloadUrl!, savePath, deleteOnError: true);
      await _updateInitBox(initDataBox, el, savePath);
      pb.incr();
    }

    Logger.log(
        LogType.info, 'Download complete; performing post download tasks...');
    if (!(argResults?['safe'] as bool)) {
      await _removeRedundantFiles(initDataBox, allContent);
    }
    _swapExe(binDir);

    Logger.log(LogType.info,
        'Done! Rush was successfully upgraded to ${releaseInfo.name}');
  }

  /// Returns a list of all the files that needs to be downloaded from GH.
  Future<List<RepoContent>> _reqContents(
      Box initDataBox, List<RepoContent> contents, bool force) async {
    // If this is a forceful upgrade, return all the files, else only the ones
    // that have changed.
    if (force) {
      return contents;
    }

    final res = <RepoContent>[];
    for (final el in contents) {
      final data = await initDataBox.get(el.name);

      // Stage this file for download if: 1. data is null or 2. it's sha doesn't
      // match with that of upstream or 3. it doesn't exist at the expected
      // location.
      if (data == null) {
        res.add(el);
      } else {
        final idealPath = File(p.join(_dataDir, el.path));
        if (el.sha != data['sha'] || !idealPath.existsSync()) {
          res.add(el);
        }
      }
    }

    return res;
  }

  /// Removes all the files that are no longer needed.
  Future<void> _removeRedundantFiles(
      Box initDataBox, List<RepoContent> contents) async {
    final entriesInBox = initDataBox.keys;

    final devDepsToRemove = Directory(p.join(_dataDir, 'dev-deps'))
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => !contents.any((el) =>
            el.path ==
            p.relative(file.path, from: _dataDir).replaceAll('\\', '/')));

    final toolsToRemove = Directory(p.join(_dataDir, 'tools'))
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => !contents.any((el) =>
            el.path ==
            p.relative(file.path, from: _dataDir).replaceAll('\\', '/')));

    for (final file in [...devDepsToRemove, ...toolsToRemove]) {
      // Remove box entry of this file if it exists
      final basename = p.basename(file.path);
      if (entriesInBox.contains(basename)) {
        await initDataBox.delete(basename);
      }

      try {
        file.deleteSync();
      } catch (_) {}
    }
  }

  /// Returns all the files that are changed since the last release and needs to
  /// be updated.
  Future<List<RepoContent>> _fetchAllContent(Box initDataBox) async {
    final Response response;
    try {
      response = await Dio().get('$_endpt/contents');
    } catch (e) {
      Logger.log(LogType.erro, 'Something went wrong:');
      Logger.log(LogType.erro, e.toString(), addPrefix: false);
      exit(1);
    }

    final json = response.data as List;

    final contents = json
        .map((el) => RepoContent.fromJson(el as Map<String, dynamic>))
        .where((el) {
      if (el.path!.startsWith('exe')) {
        return el.path!.contains(_correctExePath());
      }
      return true;
    });

    return contents.toList();
  }

  String _correctExePath() {
    switch (Platform.operatingSystem) {
      case 'windows':
        return 'exe/win';
      case 'macos':
        return 'exe/mac';
      default:
        return 'exe/linux';
    }
  }

  /// Replaces the old `rush.exe` with new one on Windows.
  Future<void> _swapExe(String binDir) async {
    final ext = Platform.isWindows ? '.exe' : '';

    final old = File(p.join(binDir, 'rush' + ext));
    final _new = File(p.join(binDir, 'rush' + ext + '.new'));

    if (Platform.isWindows) {
      // Replace old swap.exe with new if it exists.
      final newSwap = p.join(binDir, 'swap.exe.new');
      if (File(newSwap).existsSync()) {
        final oldSwap = File(p.join(binDir, 'swap.exe'))..createSync();
        oldSwap.deleteSync();
        File(newSwap).renameSync(oldSwap.path);
      }

      final args = <String>[];
      args
        ..add(p.join(binDir, 'swap.exe'))
        ..addAll(['-o', old.path]);

      await ProcessRunner()
          .runProcess(args, startMode: ProcessStartMode.detached);
    } else {
      old.deleteSync();
      _new.renameSync(old.path);
      _chmodExe(old.path);
    }
  }

  /// Returns a [GhRelease] containing the information of the latest `rush-cli`
  /// repo's release on GitHub.
  Future<GhRelease> _fetchLatestRelease() async {
    final Response response;
    try {
      response = await Dio().get('$_endpt/release');
    } catch (e) {
      Logger.log(LogType.erro, 'Something went wrong:');
      Logger.log(LogType.erro, e.toString(), addPrefix: false);
      exit(1);
    }

    final json = response.data as Map<String, dynamic>;
    return GhRelease.fromJson(json);
  }

  /// Updates init box's values.
  Future<void> _updateInitBox(
      Box initBox, RepoContent content, String savePath) async {
    final value = {
      'path': savePath,
      'sha': content.sha!,
    };

    await initBox.put(content.name, value);
  }

  /// Grants Rush binary execution permission on Unix systems.
  Future<void> _chmodExe(String exePath) async {
    Process.runSync('chmod', ['+x', exePath]);
  }
}
