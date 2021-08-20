import 'dart:io' show Directory, File, exit;

import 'package:archive/archive.dart';
import 'package:args/args.dart';
import 'package:checked_yaml/checked_yaml.dart';
import 'package:dart_console/dart_console.dart' show ConsoleColor;
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/commands/build/models/rush_lock.dart';
import 'package:rush_cli/commands/build/models/rush_yaml.dart';
import 'package:rush_cli/helpers/cmd_utils.dart';
import 'package:rush_cli/templates/intellij_files.dart';
import 'package:rush_prompt/rush_prompt.dart';

class BuildUtils {
  /// Returns `true` if rush.yml and AndroidManifest.xml is modified.
  static Future<bool> areInfoFilesModified(String cd, Box dataBox) async {
    final File rushYml;
    try {
      rushYml = getRushYaml(cd);
    } catch (e) {
      rethrow;
    }

    final isYmlMod = rushYml
        .lastModifiedSync()
        .isAfter(await dataBox.get('rushYmlLastMod') as DateTime);

    final manifestFile = File(p.join(cd, 'src', 'AndroidManifest.xml'));
    final isManifestMod = manifestFile
        .lastModifiedSync()
        .isAfter(await dataBox.get('manifestLastMod') as DateTime);

    final res = isYmlMod || isManifestMod;

    if (res) {
      await Future.wait([
        dataBox.put('rushYmlLastMod', rushYml.lastModifiedSync()),
        dataBox.put('manifestLastMod', manifestFile.lastModifiedSync())
      ]);
    }

    return res;
  }

  /// Cleans workspace dir for the given [org].
  static void cleanWorkspaceDir(String dataDir, String org) {
    final dir = Directory(p.join(dataDir, 'workspaces', org));

    if (dir.existsSync()) {
      try {
        dir.deleteSync(recursive: true);
      } catch (e) {
        Logger.log(LogType.erro,
            'Something went wrong while invalidating build caches.\n${e.toString()}');
        exit(1);
      }
    }
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
          'Unsupported value for key "number" in field "version": $extVersion.\n'
          'Value MUST be either a positive integer or `auto`.');
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

  /// Gets time difference between the given two `DateTime`s.
  static String getTimeDifference(DateTime timeOne, DateTime timeTwo) {
    final diff = timeTwo.difference(timeOne).inMilliseconds;

    final brightBlack = '\u001b[30;1m';
    final cyan = '\u001b[36m';
    final reset = '\u001b[0m';

    final seconds = diff ~/ 1000;
    final millis = diff % 1000;

    var res = '$brightBlack[$reset';
    res += cyan;
    if (seconds > 0) {
      res += '${seconds}s ';
    }
    res += '${millis}ms';
    res += '$brightBlack]$reset';

    return res;
  }

  /// Returns `true` if the current extension needs to be optimized.
  static bool needsOptimization(
      bool isRelease, ArgResults args, RushYaml yaml) {
    if (args['no-optimize'] as bool) {
      return false;
    }

    if (args['optimize'] as bool) {
      return true;
    }

    if (isRelease && (yaml.build?.release?.optimize ?? false)) {
      return true;
    }

    return false;
  }

  /// Prints "• Build Failed" to the console
  static void printFailMsg(String timeDiff) {
    final store = ErrWarnStore();

    final brightBlack = '\u001b[30;1m';
    final red = '\u001b[31m';
    final yellow = '\u001b[33m';
    final reset = '\u001b[0m';

    var errWarn = '$brightBlack[$reset';

    if (store.getErrors > 0) {
      errWarn += red;
      errWarn += store.getErrors > 1
          ? '${store.getErrors} errors'
          : '${store.getErrors} error';
      errWarn += reset;

      if (store.getWarnings > 0) {
        errWarn += '$brightBlack;$reset ';
      }
    }

    if (store.getWarnings > 0) {
      errWarn += yellow;
      errWarn += store.getWarnings > 1
          ? '${store.getWarnings} warnings'
          : '${store.getWarnings} warning';
      errWarn += reset;
    }

    errWarn = errWarn.length == 1 ? '' : '$errWarn$brightBlack]$reset';

    Logger.logCustom('Build failed $timeDiff $errWarn',
        prefix: '\n• ', prefixFG: ConsoleColor.red);
  }

  /// Delete's everything inside the build box.
  static Future<void> emptyBuildBox() async {
    final buildBox = await Hive.openBox('build');
    await buildBox.delete('alreadyPrinted');
  }

  /// Checks whether the .idea/libraries/dev_deps.xml file defines the correct
  /// dev deps and updates it if required. This is required since Rush v1.2.2
  /// as this release centralized the dev deps directory for all the Rush projects.
  /// So, therefore, to not break IDE features for old projects, this file needs
  /// to point to the correct location of dev deps.
  static void updateDevDepsXml(String cd, String dataDir) {
    final devDepsXmlFile = () {
      final file = File(p.join(cd, '.idea', 'libraries', 'dev-deps.xml'));
      if (file.existsSync()) {
        return file;
      } else {
        return File(p.join(cd, '.idea', 'libraries', 'dev_deps.xml'))
          ..createSync(recursive: true);
      }
    }();

    final devDepsXml = getDevDepsXml(dataDir);
    if (devDepsXmlFile.readAsStringSync() != devDepsXml) {
      CmdUtils.writeFile(devDepsXmlFile.path, devDepsXml);
    }
  }

  static List<String> getDepJarPaths(
      String cd, RushYaml rushYaml, DepScope scope) {
    final allEntries = rushYaml.deps?.where((el) => el.scope() == scope);
    final localJars = allEntries
            ?.where((el) => !el.value().contains(':'))
            .map((el) => p.join(cd, 'deps', el.value())) ??
        [];

    final RushLock lockFile;
    try {
      lockFile = checkedYamlDecode(
          File(p.join(cd, '.rush', 'rush.lock')).readAsStringSync(),
          (json) => RushLock.fromJson(json!));
    } catch (e) {
      Logger.log(LogType.erro, e.toString());
      exit(1);
    }

    final remoteJars = lockFile.resolvedDeps
        .where((el) => el.scope == scope.value())
        .map((el) {
      if (el.type == 'aar') {
        return _extractJar(el.localPath);
      }
      return el.localPath;
    });

    return [...localJars, ...remoteJars];
  }

  static String classpathStringForDeps(
      String cd, String dataDir, RushYaml rushYaml) {
    final depJars = [
      ...getDepJarPaths(cd, rushYaml, DepScope.implement),
      ...getDepJarPaths(cd, rushYaml, DepScope.compileOnly)
    ];

    final devDepsDir = Directory(p.join(dataDir, 'dev-deps'));
    for (final el in devDepsDir.listSync(recursive: true)) {
      if (el is File) {
        depJars.add(el.path);
      }
    }

    return depJars.join(CmdUtils.cpSeparator());
  }

  static String _extractJar(String aarPath) {
    final archive = ZipDecoder().decodeBytes(File(aarPath).readAsBytesSync());
    final classesJar =
        archive.files.firstWhere((el) => el.isFile && el.name == 'classes.jar');
    final jar = File(p.join(
        p.dirname(aarPath), p.basenameWithoutExtension(aarPath) + '.jar'));
    jar
      ..createSync(recursive: true)
      ..writeAsBytesSync(classesJar.content as List<int>);
    return jar.path;
  }
}
