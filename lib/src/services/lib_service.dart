import 'dart:io'
    show
        FileLock,
        FileMode,
        FileSystemException,
        Platform,
        Process,
        RandomAccessFile;

import 'package:archive/archive.dart';

import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:collection/collection.dart';

import 'package:rush/src/commands/build/utils.dart';
import 'package:rush/src/config/config.dart';
import 'package:rush/src/services/ai2_runtime.dart';
import 'package:rush/src/resolver/artifact.dart';
import 'package:rush/src/services/file_service.dart';
import 'package:rush/src/services/logger.dart';
import 'package:rush/src/utils/constants.dart';
import 'package:rush/src/utils/file_extension.dart';
import 'package:tint/tint.dart';

const r8Coord = 'com.android.tools:r8:9.4.24';
const pgCoord = 'com.guardsquare:proguard-base:7.10.0';
const coreLibraryCoord = 'com.android.tools:desugar_jdk_libs:2.1.5';
const coreLibraryConfigCoord =
    'com.android.tools:desugar_jdk_libs_configuration:2.1.5';
final aapt2Coord = 'com.android.tools.build:aapt2:jar:'
    '${Platform.isWindows ? 'windows' : Platform.isMacOS ? 'osx' : 'linux'}'
    ':8.13.2-14304508';

const manifMergerAndDeps = <String>[
  'com.android.tools.build:manifest-merger:32.4.0',
];

const kotlinGroupId = 'org.jetbrains.kotlin';

class LibService {
  static final _fs = GetIt.I<FileService>();
  static final _lgr = GetIt.I<Logger>();

  LibService._() {
    Hive
      ..registerAdapter(ArtifactAdapter())
      ..registerAdapter(ScopeAdapter());

    // Don't init Hive in .rush dir if we're not in a rush project
    if (_fs.configFile.existsSync()) {
      Hive.init(_fs.dotRushDir.path);
    }
  }

  late final LazyBox<Artifact>? extensionDepsBox;
  late Map<String, Artifact> _buildLibs;

  static Future<LibService> instantiate() async {
    final instance = LibService._();
    await instance.updateBuildLibs((_) async {});

    if (await _fs.configFile.exists()) {
      instance.extensionDepsBox = await Hive.openLazyBox<Artifact>(
        extensionDepsBoxName,
        path: _fs.dotRushDir.path,
      );
    } else {
      instance.extensionDepsBox = null;
    }
    return instance;
  }

  Future<void> updateBuildLibs(
      Future<void> Function(LazyBox<Artifact> box) update) async {
    final cacheDir = p.join(_fs.rushHomeDir.path, 'cache').asDir(true);
    final lock = await p
        .join(cacheDir.path, '$buildLibsBoxName.access')
        .asFile(true)
        .open(mode: FileMode.write);
    try {
      await _acquire(lock);
      final box = await Hive.openLazyBox<Artifact>(buildLibsBoxName,
          path: cacheDir.path);
      try {
        await update(box);
        _buildLibs = {
          for (final artifact in await _retrieveArtifactsFromBox(box))
            artifact.coordinate: artifact
        };
      } finally {
        await box.close();
      }
    } finally {
      await lock.close();
    }
  }

  static Future<void> _acquire(RandomAccessFile lock) async {
    try {
      await lock.lock(FileLock.exclusive);
    } on FileSystemException {
      _lgr.info(
          'Waiting for another Rush process to finish using the build tools cache...');
      await lock.lock(FileLock.blockingExclusive);
    }
  }

  /// Returns a list of all the artifacts and their dependencies in a box.
  Future<List<Artifact>> _retrieveArtifactsFromBox(
      LazyBox<Artifact> cacheBox) async {
    final artifacts = await Future.wait([
      for (final key in cacheBox.keys) cacheBox.get(key),
    ]);
    return artifacts.whereNotNull().toList();
  }

  Future<List<Artifact>> providedDependencies(Config? config) async => [
        _rushAnnotations,
        ...(await Ai2Runtime.load()).libs,
        if (config != null) ...await projectProvidedDependencies(config),
      ];

  Future<List<Artifact>> dependenciesInEveryApp(Config config) async => [
        ...(await Ai2Runtime.load()).alwaysIncludedLibs,
        ...await projectProvidedDependencies(config),
      ];

  Artifact get _rushAnnotations => Artifact(
        coordinate: 'rush-annotations',
        scope: Scope.provided,
        artifactFile: annotationsJar,
        packaging: 'jar',
        dependencies: [],
        sourcesJar: null,
      );

  Future<List<Artifact>> projectProvidedDependencies(Config config) async {
    final allExtRemoteDeps = await _retrieveArtifactsFromBox(extensionDepsBox!);
    final remote = config.providedDependencies
        .map((el) =>
            allExtRemoteDeps.firstWhereOrNull((dep) => dep.coordinate == el))
        .whereNotNull();
    final local = config.providedDependencies
        .where((el) => el.endsWith('.jar') || el.endsWith('.aar'))
        .map((el) => Artifact(
              scope: Scope.provided,
              coordinate: el,
              artifactFile: p.join(_fs.localDepsDir.path, el),
              packaging: p.extension(el).substring(1),
              dependencies: [],
              sourcesJar: null,
            ));
    return [...remote, ...local];
  }

  List<Artifact> _requiredDeps(
      Iterable<Artifact> allDeps, Iterable<Artifact> directDeps) {
    final res = <Artifact>{};
    for (final dep in directDeps) {
      final depArtifacts = dep.dependencies
          .map((el) => allDeps.firstWhereOrNull((a) => a.coordinate == el))
          .whereNotNull();
      res
        ..add(dep)
        ..addAll(_requiredDeps(allDeps, depArtifacts));
    }
    return res.toList();
  }

  Future<List<Artifact>> extensionDependencies(
    Config config, {
    bool includeAi2ProvidedDeps = false,
    bool includeProjectProvidedDeps = false,
    bool includeLocal = true,
  }) async {
    final allExtRemoteDeps = await _retrieveArtifactsFromBox(extensionDepsBox!);

    final projectDeps = config.dependencies
        .map((el) =>
            allExtRemoteDeps.firstWhereOrNull((dep) => dep.coordinate == el))
        .whereNotNull();
    final requiredDeps = _requiredDeps(allExtRemoteDeps, projectDeps);

    final localDeps = config.dependencies
        .where((el) => el.endsWith('.jar') || el.endsWith('.aar'))
        .map((el) {
      return Artifact(
        scope: Scope.compile,
        coordinate: el,
        artifactFile: p.join(_fs.localDepsDir.path, el),
        packaging: p.extension(el).substring(1),
        dependencies: [],
        sourcesJar: null,
      );
    });
    await BuildUtils.extractAars(localDeps
        .where((el) => el.packaging == 'aar')
        .map((el) => el.artifactFile));

    return [
      ...requiredDeps,
      if (includeLocal) ...localDeps,
      if (includeAi2ProvidedDeps) ...await providedDependencies(config),
      if (includeProjectProvidedDeps)
        ...await projectProvidedWithDependencies(config),
    ];
  }

  Future<List<Artifact>> projectProvidedWithDependencies(Config config) async {
    final allExtRemoteDeps = await _retrieveArtifactsFromBox(extensionDepsBox!);
    final projectProvidedDeps = config.providedDependencies
        .map((el) =>
            allExtRemoteDeps.firstWhereOrNull((dep) => dep.coordinate == el))
        .whereNotNull();
    return _requiredDeps(allExtRemoteDeps, projectProvidedDeps);
  }

  List<Artifact> buildLibArtifacts() => _buildLibs.values.toList();

  Future<Artifact> _findArtifact(String coord) async {
    final artifact = _buildLibs[coord];
    if (artifact == null || !await artifact.artifactFile.asFile().exists()) {
      _lgr
        ..err('Unable to find a required library in cache: $coord')
        ..log('Try running `rush deps sync`', 'help  '.green());
      throw Exception();
    }
    return artifact;
  }

  String get processorJar => _shippedJar('processor.jar');

  String get annotationsJar => _shippedJar('annotations.jar');

  String get relocatorJar => _shippedJar('relocator.jar');

  String _shippedJar(String name) {
    final jar = p.join(_fs.libsDir.path, name);
    if (!jar.asFile().existsSync()) {
      _lgr
        ..err('Unable to find $name in ${_fs.libsDir.path}')
        ..log('Try reinstalling Rush', 'help  '.green());
      throw Exception('$name not found');
    }
    return jar;
  }

  Future<String> r8Jar() async => (await _findArtifact(r8Coord)).classesJar;

  Future<String> coreLibraryJar() async =>
      (await _findArtifact(coreLibraryCoord)).classesJar;

  Future<String> coreLibraryConfigJar() async =>
      (await _findArtifact(coreLibraryConfigCoord)).classesJar;

  Future<String> aapt2Exe() async {
    final jar = (await _findArtifact(aapt2Coord)).classesJar;
    final exe = p.join(p.dirname(jar), p.basenameWithoutExtension(jar),
        Platform.isWindows ? 'aapt2.exe' : 'aapt2');
    if (!await exe.asFile().exists()) {
      final archive =
          ZipDecoder().decodeBytes(await jar.asFile().readAsBytes());
      await exe
          .asFile(true)
          .writeAsBytes(archive.findFile(p.basename(exe))!.content);
      if (!Platform.isWindows) {
        await Process.run('chmod', ['+x', exe]);
      }
    }
    return exe;
  }

  Future<Set<String>> pgJars() async =>
      (await _findArtifact(pgCoord)).classpathJars(buildLibArtifacts());

  Future<Set<String>> manifMergerJars() async => [
        for (final lib in manifMergerAndDeps)
          (await _findArtifact(lib)).classpathJars(buildLibArtifacts())
      ].flattened.toSet();

  Future<Set<String>> kotlincJars(String ktVersion) async =>
      (await _findArtifact(
              '$kotlinGroupId:kotlin-compiler-embeddable:$ktVersion'))
          .classpathJars(buildLibArtifacts());

  Future<Set<String>> kaptJars(String ktVersion) async => (await _findArtifact(
          '$kotlinGroupId:kotlin-annotation-processing-embeddable:$ktVersion'))
      .classpathJars(buildLibArtifacts());
}
