import 'dart:io';

import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:rush/src/services/logger.dart';
import 'package:rush/src/utils/file_extension.dart';

class FileService {
  final String cwd;
  late final Directory rushHomeDir;

  final _lgr = GetIt.I.get<Logger>();

  FileService(this.cwd) {
    final homeDir =
        (Platform.environment['RUSH_HOME'] ?? _installedHomeDir).asDir();

    if (!p.join(homeDir.path, 'libs').asDir().existsSync()) {
      _lgr.err('Could not find Rush data directory at ${homeDir.path}.');
      exit(1);
    }

    rushHomeDir = homeDir;
  }

  static String get _installedHomeDir =>
      p.dirname(p.dirname(Platform.resolvedExecutable));

  Directory get srcDir => p.join(cwd, 'src').asDir();
  Directory get resDir => p.join(cwd, 'res').asDir();
  Directory get localDepsDir => p.join(cwd, 'deps').asDir();
  Directory get dotRushDir => p.join(cwd, '.rush').asDir();

  Directory get buildDir => p.join(dotRushDir.path, 'build').asDir(true);
  Directory get buildClassesDir => p.join(buildDir.path, 'classes').asDir(true);
  Directory get buildRawDir => p.join(buildDir.path, 'raw').asDir(true);
  Directory get buildFilesDir => p.join(buildDir.path, 'files').asDir(true);
  Directory get buildKaptDir => p.join(buildDir.path, 'kapt').asDir(true);
  Directory get buildAarsDir =>
      p.join(buildDir.path, 'extracted-aars').asDir(true);

  String extractedAarDir(String aarPath) =>
      p.isWithin(localDepsDir.path, aarPath)
          ? p.join(buildAarsDir.path, p.basenameWithoutExtension(aarPath))
          : p.join(p.dirname(aarPath), p.basenameWithoutExtension(aarPath));

  File resourceFromExtractedAar(String aarPath, String resourceName) =>
      p.join(extractedAarDir(aarPath), resourceName).asFile();

  Directory get libsDir => p.join(rushHomeDir.path, 'libs').asDir();

  File get configFile {
    if (p.join(cwd, 'rush.yml').asFile().existsSync()) {
      return p.join(cwd, 'rush.yml').asFile();
    } else {
      return p.join(cwd, 'rush.yaml').asFile();
    }
  }

  File get javacArgsFile =>
      p.join(buildFilesDir.path, 'javac.args').asFile(true);
  File get kotlincArgsFile =>
      p.join(buildFilesDir.path, 'kotlinc.args').asFile(true);

  File get kaptArgsFile => p.join(buildFilesDir.path, 'kapt.args').asFile(true);
}
