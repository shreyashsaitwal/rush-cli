import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:dart_console/dart_console.dart';
import 'package:rush_prompt/rush_prompt.dart';
import 'package:yaml/yaml.dart';
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
  void copyDevDepsIfNeeded(String scriptPath, String cd) {
    final devDepsDir = Directory(p.join(cd, '.rush', 'dev-deps'));
    final devDepsCache =
        Directory(p.join(scriptPath.split('bin').first, 'dev-deps'));

    if (devDepsDir.listSync().isEmpty) {
      PrintMsg('Getting things ready...', ConsoleColor.brightWhite, '\n•',
          ConsoleColor.yellow);
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
        ThrowError(
            message:
                'ERR Something went wrong while invalidating build caches.');
      }
    }
  }

  static String getPackage(YamlMap? loadedYml, String srcDirPath, String cd) {
    final srcDir = Directory(srcDirPath);
    var path = '';

    for (final file in srcDir.listSync(recursive: true)) {
      if (file is File &&
          p.basename(file.path) == '${loadedYml!['name']}.java') {
        path = file.path;
        break;
      }
    }

    final struct = p.split(path.split(p.join(cd, 'src')).last);
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
}
