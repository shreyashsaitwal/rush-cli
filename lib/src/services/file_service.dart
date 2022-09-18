import 'dart:io';

import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/src/services/logger.dart';
import 'package:rush_cli/src/utils/file_extension.dart';

class FileService {
  final String cwd;
  late final Directory rushHomeDir;

  final _lgr = GetIt.I.get<Logger>();

  FileService(this.cwd) {
    final Directory homeDir;
    final env = Platform.environment;

    if (env.containsKey('RUSH_HOME')) {
      homeDir = env['RUSH_HOME']!.asDir();
    } else if (env.containsKey('RUSH_DATA_DIR')) {
      _lgr.warn('RUSH_DATA_DIR env var is deprecated. Use RUSH_HOME instead.');
      homeDir = env['RUSH_DATA_DIR']!.asDir();
    } else {
      if (Platform.operatingSystem == 'windows') {
        homeDir = p.join(env['UserProfile']!, '.rush').asDir();
      } else {
        homeDir = p.join(env['HOME']!, '.rush').asDir();
      }
    }

    if (!homeDir.existsSync() || homeDir.listSync().isEmpty) {
      _lgr.err('Could not find Rush data directory at $homeDir.');
      exit(1);
    }

    rushHomeDir = homeDir;
  }

  Directory get srcDir => p.join(cwd, 'src').asDir();
  Directory get localDepsDir => p.join(cwd, 'deps').asDir();
  Directory get dotRushDir => p.join(cwd, '.rush').asDir();

  Directory get buildDir => p.join(dotRushDir.path, 'build').asDir(true);
  Directory get buildClassesDir => p.join(buildDir.path, 'classes').asDir(true);
  Directory get buildRawDir => p.join(buildDir.path, 'raw').asDir(true);
  Directory get buildFilesDir => p.join(buildDir.path, 'files').asDir(true);
  Directory get buildKaptDir => p.join(buildDir.path, 'kapt').asDir(true);
  Directory get buildAarsDir =>
      p.join(buildDir.path, 'extracted-aars').asDir(true);

  Directory get libsDir => p.join(rushHomeDir.path, 'libs').asDir();

  File get configFile {
    if (p.join(cwd, 'rush.yml').asFile().existsSync()) {
      return p.join(cwd, 'rush.yml').asFile();
    } else if (p.join(cwd, 'rush.yaml').asFile().existsSync()) {
      return p.join(cwd, 'rush.yaml').asFile();
    } else {
      throw Exception('Config file rush.yaml not found');
    }
  }

  File get processorJar => p.join(libsDir.path, 'processor-uber.jar').asFile();
  File get desugarJar => p.join(libsDir.path, 'desugar.jar').asFile();

  File get jreToolsJar => p.join(libsDir.path, 'tools.jar').asFile();
  File get jreRtJar => p.join(libsDir.path, 'rt.jar').asFile();

  File get javacArgsFile =>
      p.join(buildFilesDir.path, 'javac.args').asFile(true);
  File get kotlincArgsFile =>
      p.join(buildFilesDir.path, 'kotlinc.args').asFile(true);
}
