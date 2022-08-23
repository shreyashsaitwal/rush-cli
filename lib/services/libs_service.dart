
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart';
import 'package:collection/collection.dart';

import '../resolver/artifact.dart';
import '../resolver/resolver.dart';
import 'file_service.dart';
import 'logger.dart';
import '../utils/file_extension.dart';

const _devDeps = {
  'androidx.appcompat:appcompat:1.0.0',
  'ch.acra:acra:4.9.0',
  'org.locationtech.jts:jts-core:1.16.1',
  'org.osmdroid:osmdroid-android:6.1.0',
  'redis.clients:jedis:3.1.0',
  'com.caverock:androidsvg:1.2.1',
  'com.firebase:firebase-client-android:2.5.2',
  'com.google.api-client:google-api-client:1.31.1',
  'com.google.api-client:google-api-client-android2:1.10.3-beta',
  'org.webrtc:google-webrtc:1.0.23995',
};

const _d8Coord = 'com.android.tools:r8:3.3.28';
const _pgCoord = 'com.guardsquare:proguard-base:7.2.2';
const _manifMergerCoord = 'com.android.tools.build:manifest-merger:30.2.2';

const _kotlinGroupId = 'org.jetbrains.kotlin';

class LibService {
  final _fs = GetIt.I<FileService>();

  LibService._() {
    Hive
      ..init(join(_fs.homeDir.path, 'cache'))
      ..registerAdapter(ArtifactAdapter())
      ..registerAdapter(ScopeAdapter());
  }

  static Future<LibService> instantiate() async {
    final instance = LibService._();
    instance._devDepsBox = await Hive.openBox<Artifact>('dev-deps');
    instance._buildLibsBox = await Hive.openBox<Artifact>('build-libs');
    return instance;
  }

  late final Box<Artifact> _devDepsBox;
  late final Box<Artifact> _buildLibsBox;

  final _logger = GetIt.I<Logger>();
  final _resolver = ArtifactResolver();

  bool get isCacheEmpty => _devDepsBox.isEmpty || _buildLibsBox.isEmpty;

  List<String> devDepJars() =>
      [for (final lib in _devDepsBox.values) lib.classesJar];

  String d8Jar() => _buildLibsBox.get(_d8Coord)!.classesJar;

  List<String> pgJars() => _buildLibsBox.get(_pgCoord)!.classpathJars();

  List<String> manifMergerJars() =>
      _buildLibsBox.get(_manifMergerCoord)!.classpathJars();

  List<String> kotlincJars(String ktVersion) => _buildLibsBox
      .get('$_kotlinGroupId:kotlin-compiler-embeddable:$ktVersion')!
      .classpathJars();

  String kotlinStdLib(String ktVersion) {
    return _devDepsBox
        .get('$_kotlinGroupId:kotlin-stdlib:$ktVersion')!
        .classesJar;
  }

  String kotlinAnnotationProc(String ktVersion) {
    return _buildLibsBox
        .get(
            '$_kotlinGroupId:kotlin-annotation-processing-embeddable:$ktVersion')!
        .classesJar;
  }

  Future<void> ensureDevDeps(String ktVersion) async {
    final deps = {..._devDeps, '$_kotlinGroupId:kotlin-stdlib:$ktVersion'};
    final List<Artifact> resolvedDeps;

    _logger.debug('Resolving dev deps');
    if (_devDepsBox.isEmpty) {
      resolvedDeps = await Future.wait([
        for (final dep in deps) _resolver.resolveArtifact(dep, Scope.compile)
      ]);
    } else {
      resolvedDeps = await Future.wait(_devDepsBox.values
          .whereNot((el) => el.artifactFile.asFile().existsSync())
          .map(
              (el) => _resolver.resolveArtifact(el.coordinate, Scope.compile)));
    }

    _logger.debug('Downloading and caching dev deps');
    if (resolvedDeps.isNotEmpty) {
      await Future.wait([
        for (final dep in resolvedDeps) _resolver.downloadArtifact(dep),
      ]);
      await Future.wait([
        for (final dep in resolvedDeps) _devDepsBox.put(dep.coordinate, dep),
      ]);
    }
  }

  Future<void> ensureBuildLibraries(String ktVersion) async {
    final libs = {
      '$_kotlinGroupId:kotlin-compiler-embeddable:$ktVersion',
      '$_kotlinGroupId:kotlin-annotation-processing-embeddable:$ktVersion',
      _d8Coord,
      _pgCoord,
      _manifMergerCoord,
    };

    final List<Artifact> resolvedLibs;

    _logger.debug('Resolving tools...');
    if (_buildLibsBox.isEmpty) {
      resolvedLibs = await Future.wait([
        for (final lib in libs) _resolver.resolveArtifact(lib, Scope.runtime),
      ]);
    } else {
      final resolveFuts = <Future<Artifact>>[];
      for (final lib in _buildLibsBox.values) {
        // If the library or any of its dependencies local file doesn't exist,
        // resolve it again.
        if (!lib.classesJar.asFile().existsSync() ||
            lib.dependencies
                .any((el) => !el.classesJar.asFile().existsSync())) {
          resolveFuts
              .add(_resolver.resolveArtifact(lib.coordinate, Scope.runtime));
        }
      }

      resolvedLibs = await Future.wait(resolveFuts);
    }

    _logger.debug('Downloading and caching tools...');
    if (resolvedLibs.isNotEmpty) {
      await Future.wait([
        ...resolvedLibs.map((el) => _resolver.downloadArtifact(el)),
        ...resolvedLibs.map((el) => _resolver.downloadSourceJar(el)),
        ...resolvedLibs.map((el) => _buildLibsBox.put(el.coordinate, el)),
      ]);
    }
  }
}
