import 'dart:io' show File, Directory, exit;

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:dart_console/dart_console.dart';
import 'package:rush_cli/helpers/copy.dart';
import 'package:rush_prompt/rush_prompt.dart';

class Utils {
  /// Copys the dev deps in case they are not present.
  /// This might be needed when the project is cloned from a VCS.
  void copyDevDeps(String scriptPath, String cd) {
    final devDepsDir = Directory(p.join(cd, '.rush', 'dev-deps'))
      ..createSync(recursive: true);
    final devDepsCache =
        Directory(p.join(scriptPath.split('bin').first, 'dev-deps'));

    if (devDepsDir.listSync().isEmpty) {
      Logger.log('Getting things ready...',
          color: ConsoleColor.brightWhite,
          prefix: '\n•',
          prefixFG: ConsoleColor.yellow);
      Copy.copyDir(devDepsCache, devDepsDir);
    }
  }

  /// Deletes directory located at [path] recursively.
  static void cleanDir(String path) {
    final dir = Directory(path);
    if (dir.existsSync()) {
      try {
        dir.deleteSync(recursive: true);
      } catch (e) {
        Logger.logErr(
            'Something went wrong while invalidating build caches.\n${e.toString()}',
            exitCode: 1);
      }
    }
  }

  // Returns the package name in com.example form
  static String getPackage(String extName, String srcDirPath) {
    final mainSrcFile = Directory(srcDirPath)
        .listSync(recursive: true)
        .whereType<File>()
        .singleWhere(
            (file) => p.basenameWithoutExtension(file.path) == extName);

    final path = p.relative(mainSrcFile.path, from: srcDirPath);

    final org = path
        .split(p.separator)
        .join('.')
        .split('.' + p.basename(mainSrcFile.path))
        .first;

    return org;
  }

  /// Extracts JAR file from [filePath] and saves the content to [saveTo].
  static void extractJar(String filePath, String saveTo) {
    final file = File(filePath);
    if (!file.existsSync()) {
      print('[${file.path}] doesn\'t exist. Aborting...');
      exit(1);
    }

    final bytes = file.readAsBytesSync();
    final jar = ZipDecoder().decodeBytes(bytes).files;

    for (var i = 0; i < jar.length; i++) {
      if (jar[i].isFile) {
        final data = jar[i].content;
        try {
          File(p.join(saveTo, jar[i].name))
            ..createSync(recursive: true)
            ..writeAsBytesSync(data);
        } catch (e) {
          print(e.toString());
        }
      }
    }

    file.deleteSync();
  }

  static void printFailMsg() {
    Logger.log('Build failed',
        color: ConsoleColor.brightWhite,
        prefix: '\n• ',
        prefixFG: ConsoleColor.brightRed);
  }
}
