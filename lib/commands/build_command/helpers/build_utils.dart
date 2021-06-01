import 'dart:io' show Directory, File, exit;

import 'package:path/path.dart' as p;
import 'package:hive/hive.dart';
import 'package:archive/archive.dart';
import 'package:rush_cli/commands/build_command/models/rush_yaml.dart';
import 'package:rush_cli/helpers/cmd_utils.dart';
import 'package:rush_prompt/rush_prompt.dart';
import 'package:dart_console/dart_console.dart' show ConsoleColor;

class BuildUtils {
  /// Copys the dev deps in case they are not present.
  /// This might be needed when the project is cloned from a VCS.
  static void copyDevDeps(String dataDir, String cd) {
    final devDepsDir = Directory(p.join(cd, '.rush', 'dev-deps'))
      ..createSync(recursive: true);

    final devDepsCache = Directory(p.join(dataDir, 'dev-deps'));

    if (devDepsDir.listSync().length < devDepsCache.listSync().length) {
      CmdUtils.copyDir(devDepsCache, devDepsDir);
    }
  }

  /// Cleans workspace dir for the given [org].
  static void cleanWorkspaceDir(String dataDir, String org) {
    final dir = Directory(p.join(dataDir, 'workspaces', org));

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
  }

  /// Gets time difference between the given two `DateTime`s.
  static String getTimeDifference(DateTime timeOne, DateTime timeTwo) {
    final diff = timeTwo.difference(timeOne).inMilliseconds;

    final seconds = diff ~/ 1000;
    final millis = diff % 1000;

    var res = '';
    if (seconds > 0) {
      res += '${seconds}s ';
    }
    res += '${millis}ms';

    return '[$res]';
  }

  /// Prints "• Build Failed" to the console
  static void printFailMsg(String timeDiff) {
    Logger.log('Build failed $timeDiff',
        color: ConsoleColor.brightWhite,
        prefix: '\n• ',
        prefixFG: ConsoleColor.brightRed);
  }

  /// Returns `true` if the current extension needs to be optimized.
  static bool needsOptimization(
      bool isRelease, bool optimizeArg, RushYaml yaml) {
    if (optimizeArg) {
      return true;
    }

    if (isRelease) {
      if ((yaml.release?.optimize ?? false) && !optimizeArg) {
        return true;
      }
    }

    return false;
  }

  /// Returns `true` if rush.yml and AndroidManifest.xml is modified.
  static Future<bool> areInfoFilesModified(String cd, Box dataBox) async {
    final rushYml;
    try {
      rushYml = getRushYaml(cd);
    } catch (e) {
      rethrow;
    }

    final isYmlMod =
        rushYml.lastModifiedSync().isAfter(await dataBox.get('rushYmlLastMod'));

    final manifestFile = File(p.join(cd, 'src', 'AndroidManifest.xml'));
    final isManifestMod = manifestFile
        .lastModifiedSync()
        .isAfter(await dataBox.get('manifestLastMod'));

    final res = isYmlMod || isManifestMod;

    if (res) {
      await Future.wait([
        dataBox.put('rushYmlLastMod', rushYml.lastModifiedSync()),
        dataBox.put('manifestLastMod', manifestFile.lastModifiedSync())
      ]);
    }

    return res;
  }

  /// Ensures that the required data exists in the data box.
  static Future<void> ensureBoxValues(String cd, Box box, RushYaml yaml) async {
    // Check extension's name
    final extName = yaml.name;
    if (!box.containsKey('name') || (await box.get('name')) != extName) {
      await box.put('name', yaml.name);
    }

    // Check extension's org
    final extOrg = CmdUtils.getPackage(extName, p.join(cd, 'src'));
    if (!box.containsKey('org') || (await box.get('org')) != extOrg) {
      await box.put('org', extOrg);
    }

    // Check extension's version number
    final extVersion = yaml.version.number;

    if (extVersion is! int && extVersion.toString().trim() != 'auto') {
      throw Exception(
          'Unsupported value for key "number" in field "version": $extVersion.\nValue MUST be either a positive integer or `auto`.');
    }

    if (!box.containsKey('version')) {
      if (extVersion is int) {
        await box.put('version', extVersion);
      } else {
        await box.put('version', 1);
      }
    } else if ((await box.get('version')) != extVersion && extVersion is int) {
      await box.put('version', extVersion);
    }

    // Check rush.yml's last modified time
    if (!box.containsKey('rushYmlLastMod') ||
        (await box.get('rushYmlLastMod')) == null) {
      final DateTime lastMod;

      final rushYml = File(p.join(cd, 'rush.yml'));
      final rushYaml = File(p.join(cd, 'rush.yaml'));

      if (rushYml.existsSync()) {
        lastMod = rushYml.lastModifiedSync();
      } else {
        lastMod = rushYaml.lastModifiedSync();
      }

      await box.put('rushYmlLastMod', lastMod);
    }

    // Check Android manifest's last modified time
    if (!box.containsKey('manifestLastMod') ||
        (await box.get('manifestLastMod')) == null) {
      final lastMod =
          File(p.join(cd, 'src', 'AndroidManifest.xml')).lastModifiedSync();

      await box.put('manifestLastMod', lastMod);
    }
  }

  /// Returns rush.yml file
  static File getRushYaml(String cd) {
    final yml = File(p.join(cd, 'rush.yml'));
    final yaml = File(p.join(cd, 'rush.yaml'));

    if (yml.existsSync()) {
      return yml;
    } else if (yaml.existsSync()) {
      return yaml;
    } else {
      throw Exception('rush.yml not found');
    }
  }
}
