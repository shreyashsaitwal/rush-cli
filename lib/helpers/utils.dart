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
    final srcDir = Directory(srcDirPath);
    var path = '';

    for (final file in srcDir.listSync(recursive: true)) {
      if (file is File && p.basename(file.path) == '$extName.java') {
        path = file.path;
        break;
      }
    }

    final struct = p.split(path.split(srcDirPath).last);
    struct.removeAt(0);

    var package = '';
    var isFirst = true;
    for (final dirName in struct) {
      if (!dirName.endsWith('.java')) {
        if (isFirst) {
          package += dirName;
          isFirst = false;
        } else {
          package += '.' + dirName;
        }
      }
    }

    return package;
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

  static void printFailMsg(String timeDiff) {
    Logger.log('Build failed in $timeDiff',
        color: ConsoleColor.brightWhite,
        prefix: '\n• ',
        prefixFG: ConsoleColor.brightRed);
  }

  /// Gets time difference between the given two DateTimes.
  static String getTimeDifference(DateTime timeOne, DateTime timeTwo) {
    final diff = timeTwo.difference(timeOne).inMilliseconds;

    final seconds = diff ~/ 1000;
    final millis = diff % 1000;

    var res = '';

    if (seconds > 0) {
      res += '$seconds s ';
    }
    res += '$millis ms';

    return res;
  }
}
