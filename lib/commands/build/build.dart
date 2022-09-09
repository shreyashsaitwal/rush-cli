import 'dart:convert';
import 'dart:io' show File;

import 'package:archive/archive_io.dart';
import 'package:collection/collection.dart';
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:tint/tint.dart';

import './utils.dart';
import './tools/compiler.dart';
import './tools/executor.dart';
import '../deps/sync.dart';
import '../rush_command.dart';
import '../../config/rush_yaml.dart';
import '../../resolver/artifact.dart';
import '../../services/libs_service.dart';
import '../../services/file_service.dart';
import '../../services/logger.dart';
import '../../utils/file_extension.dart';

class BuildCommand extends RushCommand {
  final Logger _lgr = GetIt.I<Logger>();
  final FileService _fs = GetIt.I<FileService>();
  final LibService _libService = GetIt.I<LibService>();

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
    Hive.init(p.join(_fs.cwd, '.rush'));

    _lgr.info('Loading config file');
    final config = await RushYaml.load(_fs.configFile, _lgr);
    if (config == null) {
      _lgr.stopTask(false);
      return 1;
    }

    final timestampsBox = await Hive.openBox<DateTime>('timestamps');
    final depsBox = await Hive.openBox<Artifact>('deps');

    await _libService.ensureDevDeps();
    // Re-fetch deps if they are outdated, ie, if the config file is modified
    // or if the dep artifacts are missing
    final configFileModified = timestampsBox
            .get('rush.yaml')
            ?.isBefore(_fs.configFile.lastModifiedSync()) ??
        true;
    final everyDepExists =
        depsBox.values.every((el) => el.classesJar.asFile().existsSync());

    final needFetch = configFileModified || !everyDepExists;

    final Iterable<Artifact> remoteArtifacts;
    if (needFetch) {
      final remoteDeps = {
        Scope.runtime: config.runtimeDeps
            .whereNot((el) => el.endsWith('.jar') || el.endsWith('.aar')),
        Scope.compile: config.comptimeDeps
            .whereNot((el) => el.endsWith('.jar') || el.endsWith('.aar')),
      };

      try {
        remoteArtifacts = await SyncSubCommand()
            .sync(cacheBox: depsBox, coordinates: remoteDeps);
        await timestampsBox.put('rush.yaml', DateTime.now());
      } catch (e) {
        _lgr.stopTask(false);
        return 1;
      }
    } else {
      remoteArtifacts = depsBox.values.toList();
    }

    final depAars = <String>{
      for (final dep in remoteArtifacts)
        if (dep.isAar) dep.artifactFile,
      for (final dep in [...config.runtimeDeps, ...config.comptimeDeps])
        if (dep.endsWith('.aar')) p.join(_fs.depsDir.path, dep)
    };

    final depJars = <String>{
      // Dev deps
      ..._libService.devDepJars(),
      // Remote deps
      for (final dep in remoteArtifacts) ...dep.classpathJars(remoteArtifacts),
      // Local deps
      for (final dep in [...config.runtimeDeps, ...config.comptimeDeps])
        if (dep.endsWith('.jar')) p.join(_fs.depsDir.path, dep),
      if (config.kotlin?.enable ?? false)
        _libService.kotlinStdLib(config.kotlin!.version),
    };
    _lgr.stopTask();

    _lgr.startTask('Compiling sources');
    try {
      await _mergeManifests(
          timestampsBox, config.android?.minSdk ?? 21, depAars, needFetch);
    } catch (e) {
      _lgr.stopTask(false);
      return 1;
    }

    try {
      await _compile(config, depJars, timestampsBox);
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
      artJarPath = await _createArtJar(config, remoteArtifacts.toList());
    } catch (e) {
      _lgr.err(e.toString());
      _lgr.stopTask(false);
      return 1;
    }
    _lgr.stopTask();

    if (argResults!['optimize'] as bool) {
      _lgr.startTask('Optimizing and obfuscating the bytecode');
      try {
        await Executor.execProGuard(artJarPath, depJars);
      } catch (e) {
        _lgr.stopTask(false);
        return 1;
      }
      _lgr.stopTask();
    }

    if (config.desugar) {
      _lgr.startTask('Desugaring Java8 langauge features');
      try {
        await Executor.execDesugarer(artJarPath, depJars);
      } catch (e) {
        _lgr.stopTask(false);
        return 1;
      }
      _lgr.stopTask();
    }

    _lgr.startTask('Generating DEX bytecode');
    try {
      await Executor.execD8(artJarPath);
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
    Box<DateTime> timestampBox,
    int minSdk,
    Iterable<String> depAars,
    bool wereNewDepsAdded,
  ) async {
    final depManifestPaths = depAars.map((path) {
      if (wereNewDepsAdded) {
        final dist = p
            .join(p.dirname(path), p.basenameWithoutExtension(path))
            .asDir(true);
        BuildUtils.unzip(path, dist.path);
      }
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

    final lastMergeTime = timestampBox.get('AndroidManifest.xml');
    _lgr.dbg('Last manifest merge time: $lastMergeTime');

    final needMerge = !await outputManifest.exists() ||
        (lastMergeTime?.isBefore(mainManifest.lastModifiedSync()) ?? true) ||
        wereNewDepsAdded;

    _lgr.info('Merging Android manifests...');

    if (!needMerge) {
      return;
    }

    await outputManifest.create(recursive: true);
    await Executor.execManifMerger(minSdk, mainManifest.path, depManifestPaths);

    await timestampBox.put('AndroidManifest.xml', DateTime.now());
  }

  /// Compiles extension's source files.
  Future<void> _compile(
    RushYaml rushYaml,
    Set<String> depJars,
    Box<DateTime> timestampBox,
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
        final isKtEnabled = rushYaml.kotlin?.enable ?? false;
        if (!isKtEnabled) {
          _lgr.err(
              'Kotlin support is not enabled in the config file rush.yaml');
          throw Exception();
        }

        await Compiler.compileKtFiles(
            depJars, rushYaml.kotlin!.version, timestampBox);
      }

      if (javaFiles.isNotEmpty) {
        await Compiler.compileJavaFiles(
            depJars, rushYaml.desugar, timestampBox);
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<String> _createArtJar(
      RushYaml rushYaml, List<Artifact> remoteArtifacts) async {
    final artJarPath =
        p.join(_fs.buildRawDir.path, 'files', 'AndroidRuntime.jar');

    final runtimeDepJars = <String>{
      ...rushYaml.runtimeDeps
          .where((dep) => dep.endsWith('.jar') || dep.endsWith('.aar'))
          .map((dep) => p.join(_fs.depsDir.path, dep)),
      ...remoteArtifacts
          .where((dep) => dep.scope == Scope.runtime)
          .map((dep) => dep.classpathJars(remoteArtifacts))
          .flattened,
    };

    final zipEncoder = ZipFileEncoder()..create(artJarPath);
    // Add class files from all required runtime deps into the ART.jar
    if (runtimeDepJars.isNotEmpty) {
      _lgr.info('Merging dependencies into a single JAR...');

      final addedPaths = <String>{};
      for (final jarPath in runtimeDepJars) {
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
