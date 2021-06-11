import 'dart:io' show File, Platform, Process, exit, stdin, stdout;

import 'package:dio/dio.dart';
import 'package:github/github.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/env.dart';
import 'package:rush_prompt/rush_prompt.dart';

class UpgradeUtils {
  /// Fetches the contents of shreyashsaitwal/rush-pack GitHub repo and
  /// return a list of those files that were updated.
  static Future<List<GitHubFile>> fetchContents(
      Box box, String dataDir, String path) async {
    final gh = GitHub(auth: Authentication.withToken(GH_PAT));
    final contents = <GitHubFile>[];

    final res = await gh.repositories
        .getContents(RepositorySlug('shreyashsaitwal', 'rush-pack'), path);

    final box = await Hive.openBox('init.data');

    for (final entity in res.tree!) {
      final nonOsPaths = _getNonOsPaths();

      if (entity.type == 'dir') {
        contents.addAll(await fetchContents(box, dataDir, entity.path!));
      } else if (!nonOsPaths.contains(entity.path)) {
        final boxedEntity = await box.get(entity.name) ??
            <String, String>{'sha': '', 'path': ''};

        final boxedSha = boxedEntity['sha'] ?? '';
        final boxedPath = boxedEntity['path'] ?? '';

        if (entity.path!.startsWith('exe') ||
            boxedSha != entity.sha ||
            !File(p.join(dataDir, boxedPath)).existsSync()) {
          contents.add(entity);
        }
      }
    }

    return contents;
  }

  /// Downloads [contents].
  static Future<void> downloadContents(
    List<GitHubFile> contents,
    Box box, {
    required String binDirPath,
    required String dataDirPath,
    required ProgressBar pb,
  }) async {
    for (final content in contents) {
      final savePath;

      if (content.path!.startsWith('exe')) {
        if (RegExp(r'rush(.exe)?', dotAll: false).hasMatch(content.name!)) {
          savePath = p.join(binDirPath, content.name! + '.new');
        } else {
          savePath = p.join(binDirPath, content.name);
        }
      } else {
        savePath = p.join(dataDirPath, content.path);
      }

      try {
        await Dio().download(content.downloadUrl!, savePath);
      } catch (e) {
        Logger.log(LogType.erro, e.toString());
        if (Platform.isWindows) {
          stdout.write('\nPress any key to continue... ');
          stdin.readLineSync();
        }
        exit(1);
      }
      pb.increment();

      if (!Platform.isWindows && content.path!.startsWith('exe')) {
        Process.runSync('chmod', ['+x', savePath]);
      }

      // Once the content is downloaded add it's sha and path to the box so next
      // time it doesn't get downloaded if it's not updated or deleted.
      await box.put(content.name, {'sha': content.sha!, 'path': content.path});
    }
  }

  /// Returns the combined size of files which are to be downloaded.
  /// Unit used to mebibyte (MiB).
  static int getSize(List<GitHubFile> files) {
    var res = 0;

    files.forEach((element) {
      res += element.size!;
    });

    return res ~/ 1.049e+6;
  }

  /// Returns a [Release] object corresponding to the latest Rush release.
  static Future<Release> getLatestRelease() async {
    final gh = GitHub(auth: Authentication.withToken(GH_PAT));

    final release = await gh.repositories
        .getLatestRelease(RepositorySlug('shreyashsaitwal', 'rush-cli'));

    return release;
  }

  static List<String> _getNonOsPaths() {
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
}
