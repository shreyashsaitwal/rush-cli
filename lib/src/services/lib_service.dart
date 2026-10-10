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

  late final LazyBox<Artifact> buildLibsBox;
  late final LazyBox<Artifact>? extensionDepsBox;

  static Future<LibService> instantiate() async {
    final instance = LibService._();
    instance.buildLibsBox = await Hive.openLazyBox<Artifact>(
      buildLibsBoxName,
      path: p.join(_fs.rushHomeDir.path, 'cache'),
    );

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
        if (config != null) ...await _projectProvidedDependencies(config),
      ];

  Future<List<Artifact>> dependenciesInEveryApp(Config config) async => [
        ...(await Ai2Runtime.load()).alwaysIncludedLibs,
        ...await _projectProvidedDependencies(config),
      ];

  Artifact get _rushAnnotations => Artifact(
        coordinate: 'rush-annotations',
        scope: Scope.provided,
        artifactFile: annotationsJar,
        packaging: 'jar',
        dependencies: [],
        sourcesJar: null,
      );

  Future<List<Artifact>> _projectProvidedDependencies(Config config) async {
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

    final projectProvidedDeps = config.providedDependencies
        .map((el) =>
            allExtRemoteDeps.firstWhereOrNull((dep) => dep.coordinate == el))
        .whereNotNull();
    final requiredProjectProvidedDeps =
        _requiredDeps(allExtRemoteDeps, projectProvidedDeps);

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
      if (includeProjectProvidedDeps) ...requiredProjectProvidedDeps,
    ];
  }

  Future<List<Artifact>> buildLibArtifacts() async =>
      (await _retrieveArtifactsFromBox(buildLibsBox)).toList();

  Future<Artifact> _findArtifact(LazyBox<Artifact> box, String coord) async {
    final artifact = await box.get(coord);
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

  Future<String> r8Jar() async =>
      (await _findArtifact(buildLibsBox, r8Coord)).classesJar;

  Future<Set<String>> pgJars() async =>
      (await _findArtifact(buildLibsBox, pgCoord))
          .classpathJars(await buildLibArtifacts());

  Future<Set<String>> manifMergerJars() async => [
        for (final lib in manifMergerAndDeps)
          (await _findArtifact(buildLibsBox, lib))
              .classpathJars(await buildLibArtifacts())
      ].flattened.toSet();

  Future<Set<String>> kotlincJars(String ktVersion) async =>
      (await _findArtifact(
        buildLibsBox,
        '$kotlinGroupId:kotlin-compiler-embeddable:$ktVersion',
      ))
          .classpathJars(await buildLibArtifacts());

  Future<Set<String>> kaptJars(String ktVersion) async => (await _findArtifact(
        buildLibsBox,
        '$kotlinGroupId:kotlin-annotation-processing-embeddable:$ktVersion',
      ))
          .classpathJars(await buildLibArtifacts());
}
