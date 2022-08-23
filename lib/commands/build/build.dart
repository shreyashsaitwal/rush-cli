import 'dart:convert';
import 'dart:io' show File, Directory, exit;

import 'package:archive/archive_io.dart';
import 'package:collection/collection.dart';
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/commands/build/utils.dart';
import 'package:rush_cli/commands/build/hive_adapters/build_box.dart';
import 'package:rush_cli/commands/deps/sync.dart';
import 'package:rush_cli/commands/rush_command.dart';
import 'package:rush_cli/config/rush_yaml.dart';
import 'package:rush_cli/commands/build/tools/compiler.dart';
import 'package:rush_cli/commands/build/tools/executor.dart';
import 'package:rush_cli/commands/build/tools/generator.dart';
import 'package:rush_cli/resolver/artifact.dart';
import 'package:rush_cli/services/file_service.dart';
import 'package:rush_cli/services/libs_service.dart';
import 'package:rush_cli/utils/file_extension.dart';
import 'package:tint/tint.dart';

import '../../services/logger.dart';

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
  Future<void> run() async {
    Hive
      ..init(p.join(_fs.cwd, '.rush'))
      ..registerAdapter(BuildBoxAdapter());

    _logger.initStep('Initializing build');

    final buildBox = await Hive.openBox<BuildBox>('build');
    if (buildBox.isEmpty) {
      await buildBox.put(0, BuildBox());
    }

    final RushYaml rushYaml;
    try {
      rushYaml = await RushYaml.load(_fs.cwd);
    } catch (e) {
      rethrow;
    }

    _kotlinVersion = rushYaml.kotlin?.version ?? '1.7.10';

    if (_libService.isCacheEmpty) {
      _logger.info('Fetching build libraries');
      await Future.wait([
        _libService.ensureDevDeps(_kotlinVersion),
        _libService.ensureBuildLibraries(_kotlinVersion),
      ]);
    }

    final remoteArtifacts =
        await SyncSubCommand().run(isHiveInit: true, rushYaml: rushYaml);

    final depAars = {
      for (final dep in remoteArtifacts)
        if (dep.isAar) dep.artifactFile,
      for (final dep in rushYaml.deps)
        if (!dep.isRemote && dep.value.endsWith('.aar'))
          p.join(_fs.depsDir.path, dep.value)
    };

    _logger.debug('Dep aars: $depAars');
    await _mergeManifests(buildBox, rushYaml.android?.minSdk ?? 21, depAars);
    _logger.closeStep();

    final depJars = {
      // Dev deps
      ..._libService.devDepJars(),
      ..._fs.libsDir.listSync().where((file) => file.path.endsWith('.jar')).map(
            (file) => file.path,
          ),
      // Remote deps
      for (final dep in remoteArtifacts) ...dep.classpathJars(),
      // Local deps
      for (final dep in rushYaml.deps)
        if (!dep.isRemote && dep.value.endsWith('.jar'))
          p.join(_fs.depsDir.path, dep.value),
    };

    _logger.initStep('Compiling sources files');
    await _compile(rushYaml, depJars);
    _logger.closeStep();

    _logger.initStep('Processing');
    await Generator.generate(rushYaml);
    final artJarPath = await _createArtJar(rushYaml, remoteArtifacts);

    if (argResults!['optimize'] as bool) {
      _logger.info('Optimizing and obfuscating the bytecode');
      await Executor.execProGuard(artJarPath, depJars);
    }

    if (rushYaml.desugar) {
      _logger.info('Desugaring the bytecode');
      await Executor.execDesugarer(artJarPath, depJars);
    }

    _logger.info('Generating DEX bytecode');
    await Executor.execD8(artJarPath);
    _logger.closeStep();

    _logger.initStep('Assembling the AIX');
    await _assemble();
    _logger.closeStep();
  }

  Future<void> _mergeManifests(
      Box<BuildBox> buildBox, int minSdk, Set<String> depAars) async {
    final depManifestPaths = depAars.map((path) {
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

    final lastMergeTime = buildBox.getAt(0)!.lastManifestMergeTime;
    _logger.debug('Last manifest merge time: $lastMergeTime');

    final hasNewManifests = depManifestPaths.any((path) {
      final file = path.asFile();
      // If the manifest file doen't exist, unzip the AAR again to get it.
      if (!file.existsSync()) {
        BuildUtils.unzip('${p.dirname(path)}.aar', p.dirname(path));
      }

      // If the file still doesn't exist, ignore it and move on.
      if (!file.existsSync()) {
        _logger.debug('Manifest file $path not found; skipping it');
        depManifestPaths.remove(path);
        return false;
      }

      return file.lastModifiedSync().isAfter(lastMergeTime);
    });

    final needMerge = !await outputManifest.exists() ||
        mainManifest.lastModifiedSync().isAfter(lastMergeTime) ||
        hasNewManifests;

    if (needMerge) {
      _logger.info('Merging Android manifests...');
      try {
        await outputManifest.create(recursive: true);
        await Executor.execManifMerger(
            minSdk, mainManifest.path, depManifestPaths);
      } catch (e) {
        rethrow;
      }
    } else {
      _logger.info('Merging Android manifests... ${'UP-TO-DATE'.green()}');
    }
  }

  /// Compiles extension's source files.
  Future<void> _compile(RushYaml rushYaml, Set<String> depJars) async {
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

        await Compiler.compileKtFiles(depJars, _kotlinVersion);
      }

      if (javaFiles.isNotEmpty) {
        await Compiler.compileJavaFiles(depJars);
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<String> _createArtJar(
      RushYaml rushYaml, List<Artifact> remoteArtifacts) async {
    final pathEndsToIgnore = [
      '.kotlin_module',
      'META-INF/versions',
      '.jar',
    ];

    final artJarPath =
        p.join(_fs.buildRawDir.path, 'files', 'AndroidRuntime.jar');
    final zipEncoder = ZipFileEncoder()..create(artJarPath);

    final runtimeDepJars = {
      ...rushYaml.deps
          .where((dep) => !dep.isRemote && dep.scope == Scope.runtime)
          .map((dep) => p.join(_fs.depsDir.path, dep.value)),
      ...remoteArtifacts
          .where((dep) => dep.scope == Scope.runtime)
          .map((dep) => dep.classpathJars())
          .flattened,
    };

    // Add Kotlin Stdlib. to runtime deps if Kotlin is enabled for the project.
    if (rushYaml.kotlin?.enable ?? false) {
      runtimeDepJars.add(_libService.kotlinStdLib(_kotlinVersion));
    }

    // Add class files from all required runtime deps into the ART.jar
    if (runtimeDepJars.isNotEmpty) {
      _logger.info('Attaching dependencies');

      for (final jarPath in runtimeDepJars) {
        final jar = jarPath.asFile();
        if (!jar.existsSync()) {
          _logger
            ..error('Unable to find required library \'$jar)\'')
            ..closeStep(fail: true);
          exit(1);
        }

        final decodedJar =
            ZipDecoder().decodeBytes(await jar.readAsBytes()).files;
        for (final file in decodedJar) {
          if (!pathEndsToIgnore.any((el) => file.name.endsWith(el))) {
            // file.decompress(); TODO: See if this works
            zipEncoder.addArchiveFile(file);
          }
        }
      }
    }

    // Add extension classes to ART.jar
    final classFiles = _fs.buildClassesDir.listSync(recursive: true);
    for (final file in classFiles) {
      if (file is File &&
          !pathEndsToIgnore.any((el) => file.path.endsWith(el))) {
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
