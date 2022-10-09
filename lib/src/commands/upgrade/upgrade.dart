import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:args/command_runner.dart';
import 'package:get_it/get_it.dart';
import 'package:github/github.dart';
import 'package:collection/collection.dart';
import 'package:http/http.dart';
import 'package:path/path.dart' as p;

import 'package:rush_cli/src/services/logger.dart';
import 'package:rush_cli/src/utils/file_extension.dart';
import 'package:rush_cli/src/services/file_service.dart';
import 'package:rush_cli/src/version.dart';
import 'package:tint/tint.dart';

class UpgradeCommand extends Command<int> {
  final _fs = GetIt.I<FileService>();
  final _lgr = GetIt.I<Logger>();

  UpgradeCommand() {
    argParser
      ..addFlag('force',
          abbr: 'f',
          help: 'Upgrades Rush even if you\'re using the latest version.')
      ..addOption('access-token',
          abbr: 't',
          help: 'Your GitHub access token. Normally, you don\'t need this.');
  }

  @override
  String get description => 'Upgrades Rush to the latest available version.';

  @override
  String get name => 'upgrade';

  @override
  Future<int> run() async {
    _lgr.info('Checking for new version');

    final gh = GitHub(
        auth: Authentication.withToken(argResults!['access-token'] as String?));
    final release = await gh.repositories
        .getLatestRelease(RepositorySlug.full('shreyashsaitwal/rush-cli'));

    final latestVersion = release.tagName;
    final force = (argResults!['force'] as bool);

    if (latestVersion == 'v$packageVersion') {
      if (!force) {
        _lgr.info(
            'You\'re already on the latest version of Rush. Use `--force` to upgrade anyway.');
        return 0;
      }
    } else {
      _lgr.info('A newer version is available: $latestVersion');
    }

    final archive =
        release.assets?.firstWhereOrNull((el) => el.name == archiveName());
    if (archive == null || archive.browserDownloadUrl == null) {
      _lgr
        ..err('Could not find asset ${archiveName()} at ${release.htmlUrl}')
        ..log('This is not supposed to happen. Please report this issue.');
      return 1;
    }

    _lgr.info('Downloading ${archiveName()}...');
    final archiveDist =
        p.join(_fs.rushHomeDir.path, 'temp', archive.name).asFile();
    try {
      final response = await get(Uri.parse(archive.browserDownloadUrl!));
      if (response.statusCode != 200) {
        _lgr
          ..err('Something went wrong...')
          ..log('GET status code: ${response.statusCode}')
          ..log('GET body:\n${response.body}');
        return 1;
      }

      archiveDist
        ..createSync(recursive: true)
        ..writeAsBytesSync(response.bodyBytes);
    } catch (e) {
      _lgr
        ..err('Something went wrong...')
        ..log(e.toString());
      return 1;
    }

    // TODO: We should delete the old files.

    _lgr.info('Extracting ${p.basename(archiveDist.path)}...');

    final inputStream = InputFileStream(archiveDist.path);
    final zipDecoder = ZipDecoder().decodeBuffer(inputStream);
    for (final file in zipDecoder.files) {
      if (file.isFile) {
        final String path;
        if (file.name.endsWith('rush.exe')) {
          path = p.join(_fs.rushHomeDir.path, '$name.new');
        } else {
          path = p.join(_fs.rushHomeDir.path, name);
        }

        final outputStream = OutputFileStream(path);
        file.writeContent(outputStream);
        await outputStream.close();
      }
    }
    await inputStream.close();
    archiveDist.deleteSync(recursive: true);

    final successMsg = '''

${'Success'.green()}! Rush $latestVersion has been installed. 🎉
Now, run ${'`rush deps sync --dev-deps`'.blue()} to re-sync dev-dependencies.

Check out the changelog for this release at: ${release.htmlUrl}
''';

    if (Platform.isWindows) {
      final newExe = '${Platform.resolvedExecutable}.new';
      if (newExe.asFile().existsSync()) {
        print(successMsg);
        await Process.start(
          'move',
          ['/Y', newExe, Platform.resolvedExecutable],
          mode: ProcessStartMode.detached,
          runInShell: true,
        );
      }
    } else {
      Process.runSync('chmod', ['+x', Platform.resolvedExecutable]);
      print(successMsg);
    }

    return 0;
  }

  String archiveName() {
    if (Platform.isWindows) {
      return 'rush-x86_64-windows.zip';
    }

    if (Platform.isLinux) {
      return 'rush-x86_64-linux.zip';
    }

    if (Platform.isMacOS) {
      final arch = Process.runSync('uname', ['-m'], runInShell: true);
      return 'rush-${arch.stdout.toString().trim()}-apple-darwin.zip';
    }

    throw UnsupportedError('Unsupported platform');
  }
}
