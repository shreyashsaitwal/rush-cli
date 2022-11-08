import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:collection/collection.dart';

import 'package:rush_cli/src/commands/build/utils.dart';
import 'package:rush_cli/src/config/config.dart';
import 'package:rush_cli/src/resolver/artifact.dart';
import 'package:rush_cli/src/services/file_service.dart';
import 'package:rush_cli/src/utils/constants.dart';

const rushApCoord =
    'io.github.shreyashsaitwal.rush:processor:$annotationProcVersion';
const r8Coord = 'com.android.tools:r8:3.3.28';
const pgCoord = 'com.guardsquare:proguard-base:7.2.2';
const desugarCoord = 'io.github.shreyashsaitwal:desugar:1.0.0';

const manifMergerAndDeps = <String>[
  'com.android.tools.build:manifest-merger:30.2.2',
  'org.w3c:dom:2.3.0-jaxb-1.0.6',
  'xml-apis:xml-apis:1.4.01',
];

const kotlinGroupId = 'org.jetbrains.kotlin';

class LibService {
  static final _fs = GetIt.I<FileService>();

  LibService._() {
    Hive
      ..registerAdapter(ArtifactAdapter())
      ..registerAdapter(ScopeAdapter());

    // Don't init Hive in .rush dir if we're not in a rush project
    if (_fs.configFile.existsSync()) {
      Hive.init(_fs.dotRushDir.path);
    }
  }

  static Future<LibService> instantiate() async {
    final instance = LibService._();
    instance.providedDepsBox = await Hive.openLazyBox<Artifact>(
      providedDepsBoxName,
      path: p.join(_fs.rushHomeDir.path, 'cache'),
    );
    instance.buildLibsBox = await Hive.openLazyBox<Artifact>(
      buildLibsBoxName,
      path: p.join(_fs.rushHomeDir.path, 'cache'),
    );

    if (_fs.configFile.existsSync()) {
      instance.extensionDepsBox = await Hive.openLazyBox<Artifact>(
        extensionDepsBoxName,
        path: _fs.dotRushDir.path,
      );
    }
    return instance;
  }

  late final LazyBox<Artifact> providedDepsBox;
  late final LazyBox<Artifact> buildLibsBox;
  late final LazyBox<Artifact> extensionDepsBox;

  /// Returns a list of all the artifacts and their dependencies in a box.
  Future<List<Artifact>> _retrieveArtifactsFromBox(
      LazyBox<Artifact> cacheBox) async {
    final artifacts = await Future.wait([
      for (final key in cacheBox.keys) cacheBox.get(key),
    ]);
    return artifacts.whereNotNull().toList();
  }

  Future<List<Artifact>> providedDependencies() async {
    final local = [
      'android-$androidPlatformSdkVersion.jar',
      'google-webrtc-1.0.19742.jar',
      'kawa-1.11-modified.jar',
      'mp-android-chart-3.1.0.jar',
      'osmdroid-5.6.6.jar',
      'physicaloid-library.jar',
    ].map((el) => Artifact(
          coordinate: el,
          scope: Scope.compile,
          artifactFile: p.join(_fs.libsDir.path, el),
          packaging: 'jar',
          dependencies: [],
          sourcesJar: null,
        ));

    return [
      ...await _retrieveArtifactsFromBox(providedDepsBox),
      ...local,
    ];
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
    bool includeProvided = false,
    bool includeLocal = true,
  }) async {
    final allExtRemoteDeps = await _retrieveArtifactsFromBox(extensionDepsBox);

    final directRemoteDeps = [
      ...config.comptimeDeps.map((el) {
        return allExtRemoteDeps.firstWhereOrNull(
            (dep) => dep.coordinate == el && dep.scope == Scope.compile);
      }),
      ...config.runtimeDeps.map((el) {
        return allExtRemoteDeps.firstWhereOrNull(
            (dep) => dep.coordinate == el && dep.scope == Scope.runtime);
      }),
    ].whereNotNull();
    final requiredRemoteDeps =
        _requiredDeps(allExtRemoteDeps, directRemoteDeps);

    final localDeps = [
      ...config.comptimeDeps
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
      }),
      ...config.runtimeDeps
          .where((el) => el.endsWith('.jar') || el.endsWith('.aar'))
          .map((el) {
        return Artifact(
          scope: Scope.runtime,
          coordinate: el,
          artifactFile: p.join(_fs.localDepsDir.path, el),
          packaging: p.extension(el).substring(1),
          dependencies: [],
          sourcesJar: null,
        );
      }),
    ];
    BuildUtils.extractAars(localDeps
        .where((el) => el.packaging == 'aar')
        .map((el) => el.artifactFile));

    return [
      ...requiredRemoteDeps,
      if (includeLocal) ...localDeps,
      if (includeProvided) ...await providedDependencies(),
    ];
  }

  Future<List<Artifact>> buildLibArtifacts() async =>
      (await _retrieveArtifactsFromBox(buildLibsBox)).toList();

  Future<String> processorJar() async =>
      (await buildLibsBox.get(rushApCoord))!.classesJar!;

  Future<String> r8Jar() async =>
      (await buildLibsBox.get(r8Coord))!.classesJar!;

  Future<Iterable<String>> pgJars() async => (await buildLibsBox.get(pgCoord))!
      .classpathJars(await buildLibArtifacts());

  Future<String> desugarJar() async =>
      (await buildLibsBox.get(desugarCoord))!.classesJar!;

  Future<Iterable<String>> manifMergerJars() async => [
        for (final lib in manifMergerAndDeps)
          (await buildLibsBox.get(lib))!
              .classpathJars(await buildLibArtifacts())
      ].flattened;

  Future<Iterable<String>> kotlincJars(String ktVersion) async =>
      (await buildLibsBox
              .get('$kotlinGroupId:kotlin-compiler-embeddable:$ktVersion'))!
          .classpathJars(await buildLibArtifacts());

  Future<Iterable<String>> kaptJars(String ktVersion) async =>
      (await buildLibsBox.get(
              '$kotlinGroupId:kotlin-annotation-processing-embeddable:$ktVersion'))!
          .classpathJars(await buildLibArtifacts());
}
