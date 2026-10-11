import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:args/command_runner.dart';
import 'package:get_it/get_it.dart';
import 'package:github/github.dart';
import 'package:collection/collection.dart';
import 'package:http/http.dart';
import 'package:path/path.dart' as p;

import 'package:rush/src/services/logger.dart';
import 'package:rush/src/utils/constants.dart';
import 'package:rush/src/utils/file_extension.dart';
import 'package:rush/src/services/file_service.dart';
import 'package:rush/src/version.dart';
import 'package:tint/tint.dart';

Future<void> installArchive(String archive, Directory rushHome) async {
  final input = InputFileStream(archive);
  try {
    for (final file in ZipDecoder().decodeStream(input).files) {
      if (!file.isFile) {
        continue;
      }
      final destination = p.join(rushHome.path, file.name);
      final isExecutable = p.split(file.name).first == 'bin';
      final target = isExecutable ? '$destination.new' : destination;
      await Directory(p.dirname(target)).create(recursive: true);
      final output = OutputFileStream(target);
      file.writeContent(output);
      await output.close();
      if (isExecutable) {
        await _replaceExecutable(target, destination);
      }
    }
  } finally {
    await input.close();
  }
}

Future<void> _replaceExecutable(String newExe, String exe) async {
  if (Platform.isWindows && await File(exe).exists()) {
    final old = File('$exe.old');
    if (await old.exists()) {
      await old.delete();
    }
    await File(exe).rename(old.path);
  }
  await File(newExe).rename(exe);
  if (!Platform.isWindows) {
    await Process.run('chmod', ['+x', exe]);
  }
}

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
    _lgr.info('Checking for new version...');

    final gh = GitHub(
        auth: Authentication.withToken(argResults!['access-token'] as String?));
    final release =
        await gh.repositories.getLatestRelease(RepositorySlug.full(rushRepo));

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
        ..err(
            'Could not find release asset ${archiveName()} at ${release.htmlUrl}')
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

      await archiveDist.create(recursive: true);
      await archiveDist.writeAsBytes(response.bodyBytes);
    } catch (e) {
      _lgr
        ..err('Something went wrong...')
        ..log(e.toString());
      return 1;
    }

    _lgr.info('Extracting ${p.basename(archiveDist.path)}...');
    await installArchive(archiveDist.path, _fs.rushHomeDir);
    await archiveDist.parent.delete(recursive: true);

    // ignore: avoid_print
    print('''
${'Success'.green()}! Rush $latestVersion has been installed. 🎉

Now, run ${'`rush deps sync --dev-deps`'.blue()} to re-sync updated dev-dependencies.

Check out the changelog for this release at: ${release.htmlUrl}
''');

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
