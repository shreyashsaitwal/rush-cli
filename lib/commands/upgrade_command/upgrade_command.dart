import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_console/dart_console.dart';
import 'package:dio/dio.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:process_runner/process_runner.dart';
import 'package:rush_cli/commands/upgrade_command/models/repo_content.dart';
import 'package:rush_cli/commands/upgrade_command/models/gh_release.dart';
import 'package:rush_cli/env.dart';
import 'package:rush_cli/version.dart';
import 'package:rush_prompt/rush_prompt.dart';

class UpgradeCommand extends Command {
  final String _dataDir;

  UpgradeCommand(this._dataDir) {
    argParser.addFlag('force',
        abbr: 'f',
        help:
            'Forcefully upgrades Rush to the latest version. This downloads and replaces even the unchanged files.',
        defaultsTo: false);

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
      ..write('upgrade: ')
      ..resetColorAttributes()
      ..writeLine(description)
      ..writeLine()
      ..writeLine(' Usage: ')
      ..setForegroundColor(ConsoleColor.brightBlue)
      ..write('   rush ')
      ..setForegroundColor(ConsoleColor.cyan)
      ..write('upgrade ')
      ..resetColorAttributes();
  }

  @override
  Future<void> run() async {
    final isForce = argResults?['force'] as bool;

    Logger.log(LogType.info, 'Fetching data...');
    final reqContents = await _fetchReqContents(isForce);
    final releaseInfo = await _fetchLatestRelease();

    if (releaseInfo.name == 'v$rushVersion' && !isForce) {
      Logger.log(LogType.warn,
          'You already have the latest version of Rush ($rushVersion) installed.');
      Logger.log(LogType.note,
          'To perform a force upgrade, run `rush upgrade --force`');
      exit(0);
    }

    final List<Future<Response<dynamic>>> dlFutures = [];
    var dlSize = 0;

    final binDir = p.dirname(Platform.resolvedExecutable);

    for (final el in reqContents) {
      final savePath = () {
        if (el.path!.startsWith('exe')) {
          return p.join(binDir, el.name! + '.new');
        }
        return p.join(_dataDir, el.path);
      }();

      dlSize += el.size!;

      final dl = Dio().download(el.downloadUrl!, savePath);
      dlFutures.add(dl);
    }

    Logger.log(LogType.info, 'Downloading... ${dlSize ~/ 1.049e+6} MiB');
    try {
      await Future.wait(dlFutures);
    } catch (e) {
      Logger.log(LogType.erro, 'Something went wrong');
      Logger.log(LogType.erro, e.toString(), addPrefix: false);
    }

    Logger.log(
        LogType.info, 'Download complete; performing post download tasks...');
    _swapExe(binDir);

    Logger.log(LogType.info,
        'Done! Rush was successfully upgraded to ${releaseInfo.name}');
  }

  /// Returns all the files that are changed since the last release and needs to
  /// be updated.
  Future<List<RepoContent>> _fetchReqContents(bool force) async {
    final response = await Dio().get('$API_ENDPT/contents');
    final json = response.data as List;

    final initDataBox = await Hive.openBox('data.init');

    final contents =
        json.map((el) => RepoContent.fromJson(el as Map<String, dynamic>));

    // If this is not a forceful upgrade, only return the files that are changed
    // since the last upgrade, otherwise, return all files.
    if (!force) {
      final res = <RepoContent>[];

      for (final el in contents) {
        var data = await initDataBox.get(el.name);

        if (data != null) {
          final idealPath = p.join(_dataDir, el.path);
          if (el.sha != data['sha'] || !File(idealPath).existsSync()) {
            res.add(el);
          }
        } else {
          res.add(el);
        }
      }

      return res;
    }

    return contents.toList();
  }

  /// Replaces the old `rush.exe` with new one on Windows.
  Future<void> _swapExe(String binDir) async {
    final ext = Platform.isWindows ? '.exe' : '';

    final old = File(p.join(binDir, 'rush' + ext));
    final _new = File(p.join(binDir, 'rush' + ext + '.new'));

    if (Platform.isWindows) {
      // Replace old swap.exe with new if it exists.
      final newSwap = p.join(binDir, 'swap.exe.new');
      if (!File(newSwap).existsSync()) {
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
    }

    old.deleteSync();
    _new.renameSync(old.path);
  }

  /// Returns a [GhRelease] containing the information of the latest `rush-cli`
  /// repo's release on GitHub.
  Future<GhRelease> _fetchLatestRelease() async {
    final res = await Dio().get('$API_ENDPT/release');
    final json = res.data as Map<String, dynamic>;
    return GhRelease.fromJson(json);
  }
}
