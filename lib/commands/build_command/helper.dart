import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:dart_console/dart_console.dart';
import 'package:rush_prompt/rush_prompt.dart';
import 'package:rush_cli/mixins/copy_mixin.dart';

class Helper with CopyMixin {
  /// Checks if [out] is an useful ProGuard output.
  static bool isProGuardOutput(String out) {
    final useless = [
      '[proguard] ProGuard, version 7.1.0-beta1',
      '[proguard] ProGuard is released under the GNU General Public License. You therefore',
      '[proguard] must ensure that programs that link to it (net.sf.antcontrib.logic, ...)',
      '[proguard] carry the GNU General Public License as well. Alternatively, you can',
      '[proguard] apply for an exception with the author of ProGuard.',
    ];

    if (!useless.contains(out.trim()) &&
        out.startsWith(RegExp(r'\s\[proguard\]', caseSensitive: true))) {
      return true;
    }

    return false;
  }

  /// Converts the given list of decimal char codes into string list and removes
  /// empty lines from it.
  static List<String> format(List<int> charcodes) {
    final stringified = String.fromCharCodes(charcodes);
    final List res = <String>[];

    stringified.split('\r\n').forEach((el) {
      final antKeywords =
          RegExp(r'\[(javac|java|mkdir|zip)\]', caseSensitive: true);

      if ('$el'.trim().isNotEmpty) {
        res.add(el.trimRight().replaceAll(antKeywords, ''));
      }
    });

    return res as List<String>;
  }

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
      copyDir(devDepsCache, devDepsDir);
    }
  }

  /// Deletes directory located at [path] recursively.
  static void cleanDir(String path) {
    final dir = Directory(path);
    if (dir.existsSync()) {
      try {
        dir.deleteSync(recursive: true);
      } catch (e) {
        Logger.logErr('Something went wrong while invalidating build caches.',
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
}
