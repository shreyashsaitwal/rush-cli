import 'dart:convert' show jsonDecode;
import 'dart:io' show File;

import 'package:archive/archive_io.dart';
import 'package:collection/collection.dart';
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:tint/tint.dart';

import 'package:rush_cli/commands/build/utils.dart';
import 'package:rush_cli/commands/build/tools/compiler.dart';
import 'package:rush_cli/commands/build/tools/executor.dart';
import 'package:rush_cli/commands/deps/sync.dart';
import 'package:rush_cli/commands/rush_command.dart';
import 'package:rush_cli/config/config.dart';
import 'package:rush_cli/resolver/artifact.dart';
import 'package:rush_cli/services/libs_service.dart';
import 'package:rush_cli/services/file_service.dart';
import 'package:rush_cli/services/logger.dart';
import 'package:rush_cli/utils/constants.dart';
import 'package:rush_cli/utils/file_extension.dart';

const _androidManifestTimestampKey = 'android-manifest-xml';
const _configTimestampKey = 'rush-yaml';

class BuildCommand extends RushCommand {
  final Logger _lgr = GetIt.I<Logger>();
  final FileService _fs = GetIt.I<FileService>();
  late final LibService _libService;

  BuildCommand() {
    argParser.addFlag(
      'optimize',
      abbr: 'o',
      help:
          'Optimizes, shrinks and obfuscates extension\'s code using ProGuard.',
    );
  }

  @override
  String get description =>
      'Builds the extension project in current working directory.';

  @override
  String get name => 'build';

  /// Builds the extension in the current directory
  @override
  Future<int> run() async {
    _lgr.startTask('Initializing build');

    _lgr.dbg('Waiting for lib service');
    await GetIt.I.isReady<LibService>();
    _libService = GetIt.I<LibService>();

    _lgr.info('Loading config file');
    final config = await Config.load(_fs.configFile, _lgr);
    if (config == null) {
      _lgr.stopTask(false);
      return 1;
    }

    final timestampsBox = await Hive.openLazyBox<DateTime>(timestampBoxName);

    // Re-fetch deps if they are outdated, ie, if the config file is modified
    // or if the dep artifacts are missing
    final configFileModified = (await timestampsBox.get(_configTimestampKey))
            ?.isBefore(_fs.configFile.lastModifiedSync()) ??
        true;
    final everyDepExists = (await _libService.projectRemoteDepArtifacts())
        .every((el) => el.classesJar.asFile().existsSync());

    final needFetch = configFileModified || !everyDepExists;

    if (needFetch) {
      final remoteDeps = {
        Scope.runtime: config.runtimeDeps
            .whereNot((el) => el.endsWith('.jar') || el.endsWith('.aar')),
        Scope.compile: config.comptimeDeps
            .whereNot((el) => el.endsWith('.jar') || el.endsWith('.aar')),
      };

      try {
        await SyncSubCommand().sync(
          libCacheBox: _libService.projectDepsBox,
          coordinates: remoteDeps,
          saveCoordinatesAsKeys: false,
          timestampBox: timestampsBox,
          devDepArtifacts: await _libService.devDepArtifacts(),
        );
        await timestampsBox.put(_configTimestampKey, DateTime.now());
      } catch (e, s) {
        if (_lgr.debug) {
          _lgr.err(e.toString());
          _lgr.err(s.toString());
        }
        _lgr.stopTask(false);
        return 1;
      }
    }

    final comptimeDepJars =
        (await _libService.projectComptimeDepJars(config)).toSet();
    final runtimeDepJars =
        (await _libService.projectRuntimeDepJars(config)).toSet();

    _lgr.stopTask();

    _lgr.startTask('Compiling sources');
    try {
      await _mergeManifests(
        timestampsBox,
        config.android?.minSdk ?? 21,
        await _libService.projectRuntimeAars(),
      );
    } catch (e) {
      _lgr.stopTask(false);
      return 1;
    }

    try {
      await _compile(comptimeDepJars, config, timestampsBox);
    } catch (e) {
      _lgr.stopTask(false);
      return 1;
    }
    _lgr.stopTask();

    _lgr.startTask('Processing resources');
    final String artJarPath;
    try {
      BuildUtils.copyAssets(config);
      BuildUtils.copyLicense(config);
      artJarPath = await _createArtJar(config, runtimeDepJars);
    } catch (e) {
      _lgr.err(e.toString());
      _lgr.stopTask(false);
      return 1;
    }
    _lgr.stopTask();

    if (config.desugar) {
      _lgr.startTask('Desugaring Java8 langauge features');
      try {
        await Executor.execDesugarer(artJarPath, comptimeDepJars);
      } catch (e) {
        _lgr.stopTask(false);
        return 1;
      }
      _lgr.stopTask();
    }

    if (argResults!['optimize'] as bool) {
      _lgr.startTask('Optimizing and obfuscating the bytecode');
      try {
        final pgClasspath =
            (await _libService.pgJars()).join(BuildUtils.cpSeparator);
        await Executor.execProGuard(artJarPath, comptimeDepJars, pgClasspath);
      } catch (e) {
        _lgr.stopTask(false);
        return 1;
      }
      _lgr.stopTask();
    }

    _lgr.startTask('Generating DEX bytecode');
    try {
      await Executor.execD8(artJarPath, await _libService.r8Jar());
    } catch (e) {
      _lgr.stopTask(false);
      return 1;
    }
    _lgr.stopTask();

    _lgr.startTask('Packaging the extension');
    try {
      await _assemble();
    } catch (e) {
      _lgr.stopTask(false);
      return 1;
    }
    _lgr.stopTask();
    return 0;
  }

  Future<void> _mergeManifests(
    LazyBox<DateTime> timestampBox,
    int minSdk,
    Iterable<String> runtimeDepAars,
  ) async {
    final depManifestPaths = runtimeDepAars.map((path) {
      final outputDir = p.withoutExtension(path).asDir(true);
      return p.join(outputDir.path, 'AndroidManifest.xml');
    });

    if (depManifestPaths.isEmpty) {
      _lgr.dbg('No manifests found in dependencies; skipping manifest merge');
      return;
    }

    final mainManifest =
        p.join(_fs.srcDir.path, 'AndroidManifest.xml').asFile();
    final outputManifest =
        p.join(_fs.buildFilesDir.path, 'AndroidManifest.xml').asFile();

    final lastMergeTime = await timestampBox.get(_androidManifestTimestampKey);
    _lgr.dbg('Last manifest merge time: $lastMergeTime');

    final needMerge = !await outputManifest.exists() ||
        (lastMergeTime?.isBefore(mainManifest.lastModifiedSync()) ?? true);

    _lgr.info('Merging Android manifests...');

    if (!needMerge) {
      return;
    }

    await outputManifest.create(recursive: true);
    await Executor.execManifMerger(minSdk, mainManifest.path,
        depManifestPaths.toSet(), await _libService.manifMergerJars());

    await timestampBox.put(_androidManifestTimestampKey, DateTime.now());
  }

  /// Compiles extension's source files.
  Future<void> _compile(
    Set<String> comptimeJars,
    Config config,
    LazyBox<DateTime> timestampBox,
  ) async {
    final srcFiles =
        _fs.srcDir.path.asDir().listSync(recursive: true).whereType<File>();
    final javaFiles = srcFiles
        .whereType<File>()
        .where((file) => p.extension(file.path) == '.java');
    final ktFiles = srcFiles
        .whereType<File>()
        .where((file) => p.extension(file.path) == '.kt');

    final fileCount = javaFiles.length + ktFiles.length;
    _lgr.info('Picked $fileCount source file${fileCount > 1 ? 's' : ''}');

    try {
      if (ktFiles.isNotEmpty) {
        await Compiler.compileKtFiles(
            comptimeJars, config.kotlin!.compilerVersion, timestampBox);
      }

      if (javaFiles.isNotEmpty) {
        await Compiler.compileJavaFiles(
            comptimeJars, config.desugar, timestampBox);
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<String> _createArtJar(
      Config config, Iterable<String> runtimeJars) async {
    final artJarPath =
        p.join(_fs.buildRawDir.path, 'files', 'AndroidRuntime.jar');

    final zipEncoder = ZipFileEncoder()..create(artJarPath);

    // Add class files from all required runtime deps into the ART.jar
    if (runtimeJars.isNotEmpty) {
      _lgr.info('Merging dependencies into a single JAR...');

      final addedPaths = <String>{};
      for (final jarPath in runtimeJars) {
        final jar = jarPath.asFile();
        if (!jar.existsSync()) {
          throw Exception('Unable to find required library \'$jar)\'');
        }

        final decodedJar = ZipDecoder()
            .decodeBytes(jar.readAsBytesSync())
            .files
            .whereNot((el) =>
                addedPaths.contains(el.name) || el.name.startsWith('META-INF'))
            // Do not include files other than .class files.
            .where((el) {
          if (!el.isFile) {
            return true;
          }
          return p.extension(el.name) == '.class';
        });
        for (final file in decodedJar) {
          zipEncoder.addArchiveFile(file);
          addedPaths.add(file.name);
        }
      }
    }

    // Add extension classes to ART.jar
    final classFiles = _fs.buildClassesDir.listSync(recursive: true);
    for (final file in classFiles) {
      if (file is File &&
          !file.path.contains('META-INF') &&
          p.extension(file.path) == '.class') {
        final path = p.relative(file.path, from: _fs.buildClassesDir.path);
        await zipEncoder.addFile(file, path);
      }
    }

    zipEncoder.close();
    return artJarPath;
  }

  Future<void> _assemble() async {
    final org = () {
      final componentsJsonFile =
          p.join(_fs.buildDir.path, 'raw', 'components.json').asFile();

      final json = jsonDecode(componentsJsonFile.readAsStringSync());
      final type = json[0]['type'] as String;

      final split = type.split('.')..removeLast();
      return split.join('.');
    }();

    final outputDir = p.join(_fs.cwd, 'out').asDir(true);
    final aix = p.join(outputDir.path, '$org.aix');
    final zipEncoder = ZipFileEncoder()..create(aix);

    try {
      for (final file in _fs.buildRawDir.listSync(recursive: true)) {
        if (file is File) {
          final name = p.relative(file.path, from: _fs.buildRawDir.path);
          await zipEncoder.addFile(file, p.join(org, name));
        }
      }
      _lgr.info('Generated AIX file at ${aix.blue()}');
    } catch (e) {
      rethrow;
    } finally {
      zipEncoder.close();
    }
  }
}
