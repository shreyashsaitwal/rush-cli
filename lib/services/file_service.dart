import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:rush_cli/services/logger.dart';
import 'package:rush_cli/utils/file_extension.dart';

class FileService {
  final String cwd;
  final String rushHomeDir;

  FileService(this.cwd, this.rushHomeDir);

  Directory get dataDir {
    final os = Platform.operatingSystem;
    final Directory appDataDir;

    if (Platform.environment.containsKey('RUSH_DATA_DIR')) {
      appDataDir = Platform.environment['RUSH_DATA_DIR']!.asDir();
    } else {
      switch (os) {
        // TODO: Data dir should be named `.rush` and should be created in the
        // user's home directory in all OSs.
        case 'windows':
          appDataDir = p
              .join(Platform.environment['UserProfile']!, 'AppData', 'Roaming',
                  'rush')
              .asDir();
          break;
        case 'macos':
          appDataDir = p
              .join(Platform.environment['HOME']!, 'Library',
                  'Application Support', 'rush')
              .asDir();
          break;
        default:
          appDataDir = p.join(Platform.environment['HOME']!, 'rush').asDir();
          break;
      }
    }

    if (!appDataDir.existsSync() || appDataDir.listSync().isEmpty) {
      Logger().error(
          'Could not find Rush data directory at $appDataDir.\nTry re-installing Rush.');
      exit(1);
    }

    return appDataDir;
  }

  Directory get srcDir => p.join(cwd, 'src').asDir();
  Directory get depsDir => p.join(cwd, 'deps').asDir();
  Directory get dotRushDir => p.join(cwd, '.rush').asDir();

  Directory get buildDir => p.join(dotRushDir.path, 'build').asDir(true);
  Directory get buildClassesDir => p.join(buildDir.path, 'classes').asDir(true);
  Directory get buildRawDir => p.join(buildDir.path, 'raw').asDir(true);
  Directory get buildFilesDir => p.join(buildDir.path, 'files').asDir(true);
  Directory get buildKaptDir => p.join(buildDir.path, 'kapt').asDir(true);

  Directory get libsDir => p.join(rushHomeDir, 'libs').asDir();

  Directory get toolsDir => p.join(dataDir.path, 'tools').asDir();
  // Directory get devDepsDir => p.join(dataDir.path, 'dev-deps').asDir();
  // Directory get kotlincDir => p.join(toolsDir.path, 'kotlinc').asDir();

  File get processorJar => p.join(toolsDir.path, 'processor-uber.jar').asFile();
  File get jreToolsJar => p.join(toolsDir.path, 'tools.jar').asFile();
  File get jreRtJar => p.join(toolsDir.path, 'rt.jar').asFile();

  // Compiler files
  File get javacArgsFile =>
      p.join(buildFilesDir.path, 'javac.args').asFile(true);
  File get kotlincArgsFile =>
      p.join(buildFilesDir.path, 'kotlinc.args').asFile(true);
  File get kaptArgsFile => p.join(buildFilesDir.path, 'kapt.args').asFile(true);

  // File get kotlincScript => p
  //     .join(
  //         kotlincDir.path, 'bin', 'kotlinc${Platform.isWindows ? '.bat' : ''}')
  //     .asFile();

  // // Executor files
  // File get d8Jar => p.join(toolsDir.path, 'd8.jar').asFile();
  // File get pgJar => p.join(toolsDir.path, 'proguard.jar').asFile();
  // File get desugarJar => p.join(toolsDir.path, 'desugar.jar').asFile();
}
