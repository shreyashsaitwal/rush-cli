import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:collection/collection.dart';
import 'package:rush_cli/src/commands/build/utils.dart';
import 'package:rush_cli/src/config/config.dart';

import 'package:rush_cli/src/resolver/artifact.dart';
import 'package:rush_cli/src/services/file_service.dart';
import 'package:rush_cli/src/services/logger.dart';
import 'package:rush_cli/src/utils/constants.dart';
import 'package:rush_cli/src/utils/file_extension.dart';

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
  static final _lgr = GetIt.I<Logger>();

  LibService._() {
    _lgr.dbg('Initializing Hive in ${_fs.rushHomeDir.path}/cache');
    Hive
      ..init(p.join(_fs.rushHomeDir.path, 'cache'))
      ..init(_fs.dotRushDir.path)
      ..registerAdapter(ArtifactAdapter())
      ..registerAdapter(ScopeAdapter());
  }

  static Future<LibService> instantiate() async {
    _lgr.dbg('Instantiating LibService');
    final instance = LibService._();
    instance.devDepsBox = await Hive.openLazyBox<Artifact>(devDepBoxName,
        path: p.join(_fs.rushHomeDir.path, 'cache'));
    instance.buildLibsBox = await Hive.openLazyBox<Artifact>(buildLibsBoxName,
        path: p.join(_fs.rushHomeDir.path, 'cache'));
    instance.projectDepsBox = await Hive.openLazyBox<Artifact>(
        projectDepsBoxName,
        path: _fs.dotRushDir.path);
    return instance;
  }

  late final LazyBox<Artifact> devDepsBox;
  late final LazyBox<Artifact> buildLibsBox;
  late final LazyBox<Artifact> projectDepsBox;

  Future<List<Artifact>> devDepArtifacts() async {
    return [
      for (final key in devDepsBox.keys) (await devDepsBox.get(key))!,
      Artifact(
        coordinate: '',
        scope: Scope.compile,
        artifactFile: p.join(_fs.libsDir.path, 'runtime.jar'),
        sourceJar: null,
        dependencies: [],
        isAar: false,
      ),
      Artifact(
        coordinate: '',
        scope: Scope.compile,
        artifactFile: p.join(_fs.libsDir.path, 'android.jar'),
        sourceJar: null,
        dependencies: [],
        isAar: false,
      ),
      Artifact(
        coordinate: '',
        scope: Scope.compile,
        artifactFile: p.join(_fs.libsDir.path, 'kawa-1.11-modified.jar'),
        sourceJar: null,
        dependencies: [],
        isAar: false,
      ),
      Artifact(
        coordinate: '',
        scope: Scope.compile,
        artifactFile: p.join(_fs.libsDir.path, 'physicaloid-library.jar'),
        sourceJar: null,
        dependencies: [],
        isAar: false,
      )
    ];
  }

  Future<List<Artifact>> _buildLibArtifacts() async {
    return [
      for (final key in buildLibsBox.keys) (await buildLibsBox.get(key))!
    ];
  }

  Future<Iterable<String>> devDepJars() async => [
        for (final dep in await devDepArtifacts()) dep.classesJar,
      ];

  Future<String> processorUberJar() async =>
      (await buildLibsBox.get(rushApCoord))!.classesJar;

  Future<String> r8Jar() async => (await buildLibsBox.get(r8Coord))!.classesJar;

  Future<Iterable<String>> pgJars() async => (await buildLibsBox.get(pgCoord))!
      .classpathJars(await _buildLibArtifacts());

  Future<String> desugarJar() async =>
      (await buildLibsBox.get(desugarCoord))!.classesJar;

  Future<Iterable<String>> manifMergerJars() async => [
        for (final lib in manifMergerAndDeps)
          (await buildLibsBox.get(lib))!
              .classpathJars(await _buildLibArtifacts())
      ].flattened;

  Future<Iterable<String>> kotlincJars(String ktVersion) async =>
      (await buildLibsBox
              .get('$kotlinGroupId:kotlin-compiler-embeddable:$ktVersion'))!
          .classpathJars(await _buildLibArtifacts());

  Future<Iterable<String>> kaptJars(String ktVersion) async =>
      (await buildLibsBox.get(
              '$kotlinGroupId:kotlin-annotation-processing-embeddable:$ktVersion'))!
          .classpathJars(await _buildLibArtifacts());

  Future<Iterable<Artifact>> projectRemoteDepArtifacts() async {
    return [
      for (final key in projectDepsBox.keys) (await projectDepsBox.get(key))!
    ];
  }

  Future<Iterable<String>> projectRuntimeAars() async => [
        for (final dep in await projectRemoteDepArtifacts())
          if (dep.isAar) dep.artifactFile
      ];

  Future<Iterable<String>> projectRuntimeDepJars(Config config) async => [
        // Remote deps
        for (final dep in await projectRemoteDepArtifacts()) dep.classesJar,
        // Local deps
        for (final dep in config.runtimeDeps)
          if (dep.endsWith('.jar'))
            p.join(_fs.localDepsDir.path, dep)
          else if (dep.endsWith('.aar'))
            _classesJarFromLocalAar(p.join(_fs.localDepsDir.path, dep))
      ];

  Future<Iterable<String>> projectComptimeDepJars(Config config) async => [
        // Dev deps
        ...(await devDepJars()),
        // Runtime deps
        ...(await projectRuntimeDepJars(config)),
        // Local comptime deps
        for (final dep in config.runtimeDeps)
          if (dep.endsWith('.jar'))
            p.join(_fs.localDepsDir.path, dep)
          else if (dep.endsWith('.aar'))
            _classesJarFromLocalAar(p.join(_fs.localDepsDir.path, dep))
      ];

  String _classesJarFromLocalAar(String aarPath) {
    final basename = p.basenameWithoutExtension(aarPath);
    final dist = p.join(_fs.buildAarsDir.path, basename).asDir(true);
    BuildUtils.unzip(aarPath, dist.path);
    return p.join(dist.path, 'classes.jar');
  }
}
