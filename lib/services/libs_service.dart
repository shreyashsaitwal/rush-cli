import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:collection/collection.dart';

import 'package:rush_cli/resolver/artifact.dart';
import 'package:rush_cli/services/file_service.dart';
import 'package:rush_cli/services/logger.dart';
import 'package:rush_cli/utils/constants.dart';

const r8Coord = 'com.android.tools:r8:3.3.28';
const pgCoord = 'com.guardsquare:proguard-base:7.2.2';
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
      ..registerAdapter(ArtifactAdapter())
      ..registerAdapter(ScopeAdapter());
  }

  static Future<LibService> instantiate() async {
    _lgr.dbg('Instantiating LibService');
    final instance = LibService._();
    instance.devDepsBox = await Hive.openLazyBox<Artifact>(devDepBoxName);
    instance.buildLibsBox = await Hive.openLazyBox<Artifact>(buildLibsBoxName);
    return instance;
  }

  late final LazyBox<Artifact> devDepsBox;
  late final LazyBox<Artifact> buildLibsBox;

  late final devDeps = () async {
    return [for (final key in devDepsBox.keys) (await devDepsBox.get(key))!];
  }();

  late final _buildLibs = () async {
    return [
      for (final key in buildLibsBox.keys) (await buildLibsBox.get(key))!
    ];
  }();

  Future<List<String>> devDepJars() async => [
        for (final dep in await devDeps) dep.classesJar,
        p.join(_fs.libsDir.path, 'android.jar'),
        p.join(_fs.libsDir.path, 'annotations.jar'),
        p.join(_fs.libsDir.path, 'runtime.jar'),
        p.join(_fs.libsDir.path, 'kawa-1.11-modified.jar'),
        p.join(_fs.libsDir.path, 'physicaloid-library.jar')
      ];

  Future<String> d8Jar() async => (await buildLibsBox.get(r8Coord))!.classesJar;

  Future<List<String>> pgJars() async => (await buildLibsBox.get(pgCoord))!
      .classpathJars(await _buildLibs)
      .toList();

  Future<List<String>> manifMergerJars() async => [
        for (final lib in manifMergerAndDeps)
          (await buildLibsBox.get(lib))!.classpathJars(await _buildLibs)
      ].flattened.toList();

  Future<List<String>> kotlincJars(String ktVersion) async =>
      (await buildLibsBox
              .get('$kotlinGroupId:kotlin-compiler-embeddable:$ktVersion'))!
          .classpathJars(await _buildLibs)
          .toList();

  Future<String> kotlinStdLib(String ktVersion) async {
    return (await devDepsBox.get('$kotlinGroupId:kotlin-stdlib:$ktVersion'))!
        .classesJar;
  }

  Future<
      List<String>> kaptJars(String ktVersion) async => (await buildLibsBox.get(
          '$kotlinGroupId:kotlin-annotation-processing-embeddable:$ktVersion'))!
      .classpathJars(await _buildLibs)
      .toList();
}
