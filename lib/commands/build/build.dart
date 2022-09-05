import 'dart:convert';
import 'dart:io' show File, Directory, exit;

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
  final Logger _logger = GetIt.I<Logger>();
  final FileService _fs = GetIt.I<FileService>();
  final LibService _libService = GetIt.I<LibService>();

  late final String _kotlinVersion;

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
    Hive.init(p.join(_fs.cwd, '.rush'));

    _logger.initStep('Initializing build');

    final RushYaml config;
    try {
      config = await RushYaml.load(_fs.configFile);
    } catch (e) {
      rethrow;
    }

    _kotlinVersion = config.kotlin?.version ?? '1.7.10';

    await _libService.ensureDevDeps(_kotlinVersion);

    final timestampsBox = await Hive.openBox<DateTime>('timestamps');
    final depsBox = await Hive.openBox<Artifact>('deps');

    // Re-fetch deps if they are outdated, ie, if the config file is modified
    // or if the dep artifacts are missing
    final configFileModified = timestampsBox
            .get('rush.yaml')
            ?.isBefore(_fs.configFile.lastModifiedSync()) ??
        true;
    final everyDepExists = depsBox.isNotEmpty &&
        depsBox.values.every((el) => el.classesJar.asFile().existsSync());

    final Iterable<Artifact> remoteArtifacts;
    final needFetch = configFileModified || !everyDepExists;

    if (needFetch) {
      _logger.info('Fetching dependencies...');
      final remoteDeps = {
        Scope.runtime: config.runtimeDeps
            .whereNot((el) => el.endsWith('.jar') || el.endsWith('.aar')),
        Scope.compile: config.comptimeDeps
            .whereNot((el) => el.endsWith('.jar') || el.endsWith('.aar')),
      };
      remoteArtifacts = await SyncSubCommand()
          .sync(cacheBox: depsBox, coordinates: remoteDeps);
      await timestampsBox.put('rush.yaml', DateTime.now());
    } else {
      remoteArtifacts = depsBox.values.toList();
    }

    final depAars = <String>{
      for (final dep in remoteArtifacts)
        if (dep.isAar) dep.artifactFile,
      for (final dep in [...config.runtimeDeps, ...config.comptimeDeps])
        if (dep.endsWith('.aar')) p.join(_fs.depsDir.path, dep)
    };

    _logger.debug('Dep aars: $depAars');
    await _mergeManifests(
        timestampsBox, config.android?.minSdk ?? 21, depAars, needFetch);
    _logger.closeStep();

    final depJars = <String>{
      // Dev deps
      ..._libService.devDepJars(),
      // Remote deps
      for (final dep in remoteArtifacts) ...dep.classpathJars(remoteArtifacts),
      // Local deps
      for (final dep in [...config.runtimeDeps, ...config.comptimeDeps])
        if (dep.endsWith('.jar')) p.join(_fs.depsDir.path, dep),
    };

    _logger.initStep('Compiling sources files');
    await _compile(config, depJars, timestampsBox);
    _logger.closeStep();

    _logger.initStep('Processing');
    BuildUtils.copyAssets(config);
    BuildUtils.copyLicense(config);
    final artJarPath = await _createArtJar(config, remoteArtifacts.toList());

    if (argResults!['optimize'] as bool) {
      _logger.info('Optimizing and obfuscating the bytecode');
      await Executor.execProGuard(artJarPath, depJars);
    }

    if (config.desugar) {
      _logger.info('Desugaring the bytecode');
      await Executor.execDesugarer(artJarPath, depJars);
    }

    _logger.info('Generating DEX bytecode');
    await Executor.execD8(artJarPath);
    _logger.closeStep();

    _logger.initStep('Assembling the AIX');
    await _assemble();
    _logger.closeStep();
    return 0;
  }

  Future<void> _mergeManifests(
    Box<DateTime> timestampBox,
    int minSdk,
    Set<String> depAars,
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
    }).toSet();

    if (depManifestPaths.isEmpty) {
      _logger
          .debug('No manifests found in dependencies; skipping manifest merge');
      return;
    }

    final mainManifest =
        p.join(_fs.srcDir.path, 'AndroidManifest.xml').asFile();
    final outputManifest =
        p.join(_fs.buildFilesDir.path, 'AndroidManifest.xml').asFile();

    final lastMergeTime = timestampBox.get('AndroidManifest.xml');
    _logger.debug('Last manifest merge time: $lastMergeTime');

    final needMerge = !await outputManifest.exists() ||
        (lastMergeTime?.isBefore(mainManifest.lastModifiedSync()) ?? true) ||
        wereNewDepsAdded;

    if (needMerge) {
      _logger.info('Merging Android manifests...');
      try {
        await outputManifest.create(recursive: true);
        await Executor.execManifMerger(
            minSdk, mainManifest.path, depManifestPaths);
      } catch (e) {
        rethrow;
      }
      await timestampBox.put('AndroidManifest.xml', DateTime.now());
    } else {
      _logger.info('Merging Android manifests... ${'UP-TO-DATE'.green()}');
    }
  }

  /// Compiles extension's source files.
  Future<void> _compile(RushYaml rushYaml, Set<String> depJars,
      Box<DateTime> timestampBox) async {
    final srcFiles =
        Directory(_fs.srcDir.path).listSync(recursive: true).whereType<File>();
    final javaFiles = srcFiles
        .whereType<File>()
        .where((file) => p.extension(file.path) == '.java');
    final ktFiles = srcFiles
        .whereType<File>()
        .where((file) => p.extension(file.path) == '.kt');

    final fileCount = javaFiles.length + ktFiles.length;
    _logger.info('Picked $fileCount source file${fileCount > 1 ? 's' : ''}');

    try {
      if (ktFiles.isNotEmpty) {
        final isKtEnabled = rushYaml.kotlin?.enable ?? false;
        if (!isKtEnabled) {
          throw Exception('Kotlin support is not enabled in rush.yaml');
        }

        await Compiler.compileKtFiles(depJars, _kotlinVersion, timestampBox);
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
    final zipEncoder = ZipFileEncoder()..create(artJarPath);

    final runtimeDepJars = <String>{
      ...rushYaml.runtimeDeps
          .where((dep) => dep.endsWith('.jar') || dep.endsWith('.aar'))
          .map((dep) => p.join(_fs.depsDir.path, dep)),
      ...remoteArtifacts
          .where((dep) => dep.scope == Scope.runtime)
          .map((dep) => dep.classpathJars(remoteArtifacts))
          .flattened,
    };

    // Add Kotlin Stdlib. to runtime deps if Kotlin is enabled for the project.
    if (rushYaml.kotlin?.enable ?? false) {
      runtimeDepJars.add(_libService.kotlinStdLib(_kotlinVersion));
    }

    // Add class files from all required runtime deps into the ART.jar
    if (runtimeDepJars.isNotEmpty) {
      _logger.info('Attaching dependencies');

      final addedPaths = <String>{};
      for (final jarPath in runtimeDepJars) {
        final jar = jarPath.asFile();
        if (!jar.existsSync()) {
          _logger
            ..error('Unable to find required library \'$jar)\'')
            ..closeStep(fail: true);
          exit(1);
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

    final outputDir = Directory(p.join(_fs.cwd, 'out'));
    outputDir.createSync(recursive: true);

    final zipEncoder = ZipFileEncoder();
    zipEncoder.create(p.join(outputDir.path, '$org.aix'));

    _logger.info('Packing $org.aix');
    try {
      for (final file in _fs.buildRawDir.listSync(recursive: true)) {
        if (file is File) {
          final name = p.relative(file.path, from: _fs.buildRawDir.path);
          await zipEncoder.addFile(file, p.join(org, name));
        }
      }
    } catch (e) {
      rethrow;
    } finally {
      zipEncoder.close();
    }
  }
}
