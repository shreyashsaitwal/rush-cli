import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_console/dart_console.dart';
import 'package:github/github.dart';
import 'package:path/path.dart' as p;
import 'package:process_runner/process_runner.dart';
import 'package:rush_cli/installer/installer.dart';
import 'package:rush_prompt/rush_prompt.dart';

class UpgradeCommand extends Command {
  UpgradeCommand();

  @override
  String get description =>
      'Upgrades Rush and all it\'s components to the latest available version.';

  @override
  String get name => 'upgrade';

  @override
  Future<void> run() async {
    PrintArt();
    Logger.log('Fetching data\n',
        color: ConsoleColor.cyan,
        prefix: '•',
        prefixFG: ConsoleColor.brightYellow);

    final installer = Installer(false);

    final files = await installer.fetchRequiredFiles('');

    if (files.isEmpty) {
      Logger.log('You already have the latest version of Rush installed.',
          color: ConsoleColor.green);
      exit(0);
    }

    final pb =
        ProgressBar('Downloading... (${_getSize(files)} MiB)', files.length);

    final binDir = p.dirname(Platform.resolvedExecutable);

    await installer.downloadAllFiles(binDir, files, pb: pb, isUpgrade: true);

    _printFooter(await installer.getLatestRelease());

    await _swapExe(binDir);
  }

  void _printFooter(Release release) {
    final console = Console();

    console
      ..setForegroundColor(ConsoleColor.green)
      ..write('Success! ')
      ..setForegroundColor(ConsoleColor.brightWhite)
      ..writeLine('Rush has been upgraded to ${release.tagName}')
      ..resetColorAttributes();

    console
      ..writeLine()
      ..setForegroundColor(ConsoleColor.blue)
      ..writeLine('Changelog')
      ..setForegroundColor(ConsoleColor.brightWhite);

    final body = release.body!.split('\n');

    body
        .where((el) => !el.startsWith('#'))
        .toList()
        .getRange(0, body.length < 4 ? body.length : 4)
        .forEach((el) {
      console.writeLine(' ' * 2 + '- ' + el.replaceFirst('* ', ''));
    });

    console
      ..writeLine(' ' * 4 + '...')
      ..writeLine()
      ..writeLine('See the complete changelog here: ')
      ..setForegroundColor(ConsoleColor.blue)
      ..writeLine(release.htmlUrl)
      ..resetColorAttributes();
  }

  /// Swaps the old Rush executable with the new one
  Future<void> _swapExe(String binDir) async {
    final newExeExists = Directory(binDir)
        .listSync()
        .any((element) => p.extension(element.path) == '.new');

    if (newExeExists) {
      final oldExe =
          p.join(binDir, 'rush' + (Platform.isWindows ? '.exe' : ''));

      // Windows doesn't allows modifying any EXE while its running.
      // Therefore, we spawn a new process, detached from this one,
      // and run swap.exe which swaps the old exe with the new one.
      if (Platform.isWindows) {
        final args = <String>[];
        args
          ..add(p.join(binDir, 'swap.exe'))
          ..addAll(['-o', oldExe]);

        await ProcessRunner()
            .runProcess(args, startMode: ProcessStartMode.detached);
      } else {
        File(oldExe).deleteSync();
        File(oldExe + '.new').renameSync(oldExe);
      }
    }
  }

  /// Returns the combined size of files which are to be downloaded.
  /// Unit used to mebibyte (MiB).
  int _getSize(List<GitHubFile> files) {
    var res = 0;

    files.forEach((element) {
      res += element.size!;
    });

    return res ~/ 1.049e+6;
  }
}
