import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart';
import 'package:collection/collection.dart';

import '../resolver/artifact.dart';
import '../resolver/resolver.dart';
import 'file_service.dart';
import '../utils/file_extension.dart';

const _devDeps = <String>{
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
const _manifMergerAndDeps = <String>[
  'com.android.tools.build:manifest-merger:30.2.2',
  'org.w3c:dom:2.3.0-jaxb-1.0.6',
  'xml-apis:xml-apis:1.4.01',
];

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

  bool get resolutionNeeded {
    if (_devDepsBox.isEmpty || _buildLibsBox.isEmpty) {
      return true;
    }
    return !(_devDepsBox.values
            .every((element) => element.classesJar.asFile().existsSync()) &&
        _buildLibsBox.values
            .every((element) => element.classesJar.asFile().existsSync()));
  }

  List<String> devDepJars() =>
      [for (final lib in _devDepsBox.values) lib.classesJar];

  String d8Jar() => _buildLibsBox.get(_d8Coord)!.classesJar;

  List<String> pgJars() =>
      _buildLibsBox.get(_pgCoord)!.classpathJars(_buildLibsBox.values).toList();

  List<String> manifMergerJars() => _manifMergerAndDeps
      .map((el) => _buildLibsBox.get(el)!.classpathJars(_buildLibsBox.values))
      .flattened
      .toList();

  List<String> kotlincJars(String ktVersion) => _buildLibsBox
      .get('$_kotlinGroupId:kotlin-compiler-embeddable:$ktVersion')!
      .classpathJars(_buildLibsBox.values)
      .toList();

  String kotlinStdLib(String ktVersion) {
    return _devDepsBox
        .get('$_kotlinGroupId:kotlin-stdlib:$ktVersion')!
        .classesJar;
  }

  List<String> kaptJars(String ktVersion) => _buildLibsBox
      .get(
          '$_kotlinGroupId:kotlin-annotation-processing-embeddable:$ktVersion')!
      .classpathJars(_buildLibsBox.values)
      .toList();

  Future<void> _downloadAndCacheLibs(
    List<String> libCoords,
    Box<Artifact> cacheBox,
    Scope scope,
    bool downloadSources,
  ) async {
    final resolver = ArtifactResolver();

    print('Resolving libs... (size ${libCoords.length})');
    final resolvedLibs = (await Future.wait([
      for (final lib in libCoords) resolver.resolveArtifact(lib, scope),
    ]))
        .flattened
        .toSet()
        .toList();

    print('Downloading resolved artifacts... (size ${resolvedLibs.length})');
    await Future.wait([
      for (final artifact in resolvedLibs) resolver.downloadArtifact(artifact),
      if (downloadSources) ...[
        for (final artifact in resolvedLibs)
          resolver.downloadSourceJar(artifact)
      ],
    ]);

    await cacheBox.putAll(resolvedLibs
        .asMap()
        .map((key, value) => MapEntry(value.coordinate, value)));
  }

  Future<void> ensureDevDeps(String ktVersion) async {
    final deps = [..._devDeps, '$_kotlinGroupId:kotlin-stdlib:$ktVersion'];
    final buildTools = <String>[
      '$_kotlinGroupId:kotlin-compiler-embeddable:$ktVersion',
      '$_kotlinGroupId:kotlin-annotation-processing-embeddable:$ktVersion',
      _d8Coord,
      _pgCoord,
      ..._manifMergerAndDeps,
    ];
    await _buildLibsBox.clear();
    await _devDepsBox.clear();
    await Future.wait([
      _downloadAndCacheLibs(deps, _devDepsBox, Scope.compile, true),
      _downloadAndCacheLibs(buildTools, _buildLibsBox, Scope.runtime, false),
    ]);
  }
}
