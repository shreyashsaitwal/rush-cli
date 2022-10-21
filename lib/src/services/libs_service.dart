import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:collection/collection.dart';

import 'package:rush_cli/src/commands/build/utils.dart';
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
      instance.projectDepsBox = await Hive.openLazyBox<Artifact>(
        projectDepsBoxName,
        path: _fs.dotRushDir.path,
      );
    }
    return instance;
  }

  late final LazyBox<Artifact> providedDepsBox;
  late final LazyBox<Artifact> buildLibsBox;
  late final LazyBox<Artifact> projectDepsBox;

  /// Returns a list of all the artifacts and their dependencies in a box.
  Future<List<Artifact>> _retrieveArtifactsFromBox(
    LazyBox<Artifact> cacheBox,
  ) async {
    final artifacts = <Artifact?>{};
    for (final key in cacheBox.keys) {
      final artifact = await cacheBox.get(key);
      artifacts.add(artifact!);

      if (artifact.dependencies.isNotEmpty) {
        final deps = await Future.wait([
          for (final dep in artifact.dependencies) cacheBox.get(dep),
        ]);
        artifacts.addAll(deps);
      }
    }
    return artifacts.whereNotNull().toList();
  }

  Future<List<Artifact>> providedDepArtifacts() async {
    return [
      ...await _retrieveArtifactsFromBox(providedDepsBox),
      Artifact(
        coordinate: '',
        scope: Scope.compile,
        artifactFile: p.join(_fs.libsDir.path, 'android.jar'),
        sourcesJar: null,
        dependencies: [],
        packaging: 'jar',
      ),
      Artifact(
        coordinate: '',
        scope: Scope.compile,
        artifactFile: p.join(_fs.libsDir.path, 'kawa-1.11-modified.jar'),
        sourcesJar: null,
        dependencies: [],
        packaging: 'jar',
      ),
      Artifact(
        coordinate: '',
        scope: Scope.compile,
        artifactFile: p.join(_fs.libsDir.path, 'physicaloid-library.jar'),
        sourcesJar: null,
        dependencies: [],
        packaging: 'jar',
      )
    ];
  }

  Future<List<Artifact>> buildLibArtifacts() async =>
      (await _retrieveArtifactsFromBox(buildLibsBox)).toList();

  Future<Iterable<Artifact>> projectDepArtifacts() async =>
      (await _retrieveArtifactsFromBox(projectDepsBox)).toList();

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

  Future<Iterable<String>> runtimeAars(
      Iterable<String> localRuntimeDeps) async {
    final res = <String>[];

    final remote =
        (await projectDepArtifacts()).where((el) => el.scope == Scope.runtime);
    res.addAll(remote
        .where((el) => el.packaging == 'aar')
        .map((el) => el.artifactFile));

    BuildUtils.extractAars(
        localRuntimeDeps.where((el) => p.extension(el) == '.aar'));
    res.addAll(localRuntimeDeps.where((el) => p.extension(el) == '.aar').map(
          (el) => p.join(_fs.localDepsDir.path, el),
        ));

    return res;
  }

  Future<Iterable<String>> runtimeJars(
      Iterable<String> localRuntimeDeps) async {
    final res = <String>[];

    final remote =
        (await projectDepArtifacts()).where((el) => el.scope == Scope.runtime);
    res.addAll(remote.map((el) => el.classesJar!));

    res.addAll(localRuntimeDeps
        .where((el) => p.extension(el) == '.jar')
        .map((el) => p.join(_fs.localDepsDir.path, el)));
    res.addAll(localRuntimeDeps.where((el) => p.extension(el) == '.aar').map(
          (el) => p.join(_fs.buildAarsDir.path, p.basenameWithoutExtension(el),
              'classes.jar'),
        ));

    return res;
  }

  Future<Iterable<String>> comptimeAars(Iterable<String> localRuntimeDeps,
      Iterable<String> localComptimeDeps) async {
    final aars = <String>[...await runtimeAars(localRuntimeDeps)];

    final provided = await providedDepArtifacts();
    aars.addAll(provided
        .where((el) => el.packaging == 'aar')
        .map((el) => el.artifactFile));

    BuildUtils.extractAars(
        localComptimeDeps.where((el) => p.extension(el) == '.aar'));
    aars.addAll(localComptimeDeps.where((el) => p.extension(el) == '.aar'));

    return aars;
  }

  Future<Iterable<String>> comptimeJars(Iterable<String> localRuntimeDeps,
      Iterable<String> localComptimeDeps) async {
    final res = <String>[...await runtimeJars(localRuntimeDeps)];

    final provided = (await providedDepArtifacts());
    res.addAll(provided.map((el) => el.classesJar!));

    BuildUtils.extractAars(
        localComptimeDeps.where((el) => p.extension(el) == '.aar'));
    res.addAll(localComptimeDeps
        .where((el) => p.extension(el) == '.jar')
        .map((el) => p.join(_fs.localDepsDir.path, el)));
    res.addAll(localComptimeDeps.where((el) => p.extension(el) == '.aar').map(
          (el) => p.join(_fs.buildAarsDir.path, p.basenameWithoutExtension(el),
              'classes.jar'),
        ));

    return res;
  }
}
