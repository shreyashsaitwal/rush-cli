import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:resolver/resolver.dart';
import 'package:rush_cli/commands/build/hive_adapters/library_box.dart';
import 'package:collection/collection.dart';

import 'logger.dart';
import '../utils/file_extension.dart';

const _devDeps = {
  // AI2 provided androidx libraries
  'androidx.annotation:annotation:1.0.0',
  'androidx.appcompat:appcompat:1.0.0',
  'androidx.asynclayoutinflater:asynclayoutinflater:1.0.0',
  'androidx.collection:collection:1.0.0',
  'androidx.constraintlayout:constraintlayout:1.1.0',
  'androidx.constraintlayout:constraintlayout-solver:1.1.0',
  'androidx.coordinatorlayout:coordinatorlayout:1.0.0',
  'androidx.core:core:1.0.0',
  'androidx.arch.core:core-common:2.0.0',
  'androidx.arch.core:core-runtime:2.0.0',
  'androidx.cursoradapter:cursoradapter:1.0.0',
  'androidx.customview:customview:1.0.0',
  'androidx.drawerlayout:drawerlayout:1.0.0',
  'androidx.fragment:fragment:1.0.0',
  'androidx.interpolator:interpolator:1.0.0',
  'androidx.legacy:legacy-support-core-ui:1.0.0',
  'androidx.legacy:legacy-support-core-utils:1.0.0',
  'androidx.lifecycle:lifecycle-common:2.0.0',
  'androidx.lifecycle:lifecycle-livedata:2.0.0',
  'androidx.lifecycle:lifecycle-livedata-core:2.0.0',
  'androidx.lifecycle:lifecycle-runtime:2.0.0',
  'androidx.lifecycle:lifecycle-viewmodel:2.0.0',
  'androidx.loader:loader:1.0.0',
  'androidx.localbroadcastmanager:localbroadcastmanager:1.0.0',
  'androidx.print:print:1.0.0',
  'androidx.slidingpanelayout:slidingpanelayout:1.0.0',
  'androidx.swiperefreshlayout:swiperefreshlayout:1.0.0',
  'androidx.vectordrawable:vectordrawable:1.0.0',
  'androidx.vectordrawable:vectordrawable-animated:1.0.0',
  'androidx.versionedparcelable:versionedparcelable:1.0.0',
  'androidx.viewpager:viewpager:1.0.0',

  // Other AI2 provided libraries
  'ch.acra:acra:4.9.0',
  'com.caverock:androidsvg:1.2.1',
  'com.firebase:firebase-client-android:2.5.2',
  'com.google.api-client:google-api-client:1.31.1',
  'com.google.api-client:google-api-client-android2:1.10.3-beta',
  'org.locationtech.jts:jts-core:1.16.1',
  'org.osmdroid:osmdroid-android:6.1.0',
  'org.webrtc:google-webrtc:1.0.23995',
  'redis.clients:jedis:3.1.0',
  'com.google.code.gson:gson:2.1'
};

const _d8Coord = 'com.android.tools:r8:3.3.28';
const _pgCoord = 'com.guardsquare:proguard-base:7.2.2';
const _manifMergerCoord = 'com.android.tools.build:manifest-merger:30.2.2';

const _kotlinGroupId = 'org.jetbrains.kotlin';

class LibService {
  LibService._(String cacheDir) {
    Hive
      ..init(cacheDir)
      ..registerAdapter(ExtensionLibraryAdapter())
      ..registerAdapter(BuildLibraryAdapter());
  }

  static Future<LibService> instantiate(String cacheDir) async {
    final instance = LibService._(cacheDir);
    instance._devDepsBox = await Hive.openBox<ExtensionLibrary>('dev_deps');
    instance._buildLibsBox = await Hive.openBox<BuildLibrary>('build_libs');
    return instance;
  }

  late final Box<ExtensionLibrary> _devDepsBox;
  late final Box<BuildLibrary> _buildLibsBox;

  final _logger = GetIt.I<Logger>();
  final _resolver = ArtifactResolver();
  
  bool get isCacheEmpty => _devDepsBox.isEmpty || _buildLibsBox.isEmpty;

  List<String> get devDepJars =>
      [for (final lib in _devDepsBox.values) lib.jarFile];

  String get d8Jar => _buildLibsBox.get(_d8Coord)!.localFile;

  List<String> get pgJars {
    final pg = _buildLibsBox.get(_pgCoord);
    return [pg!.localFile, ...pg.dependencies.map((el) => el.localFile)];
  }

  List<String> get manifMergerJars {
    final manifMerger = _buildLibsBox.get(_manifMergerCoord);
    return [
      manifMerger!.localFile,
      ...manifMerger.dependencies.map((el) => el.localFile)
    ];
  }

  List<String> kotlincJars(String kotlinVersion) {
    final kotlincEmb = _buildLibsBox.get('$_kotlinGroupId:kotlin-compiler-embeddable:$kotlinVersion');
    return [
      kotlincEmb!.localFile,
      ...kotlincEmb.dependencies.map((el) => el.localFile)
    ];
  }

  String kotlinStdLib(String kotlinVersion) {
    return _buildLibsBox.get('$_kotlinGroupId:kotlin-stdlib:$kotlinVersion')!.localFile;
  }

  String kotlinAnnotationProc(String kotlinVersion) {
    return _buildLibsBox.get('$_kotlinGroupId:kotlin-annotation-processor:$kotlinVersion')!.localFile;
  }

  Future<void> ensureDevDeps({String? kotlinVersion}) async {
    final Set<String> deps;
    if (kotlinVersion != null) {
      deps = {..._devDeps, '$_kotlinGroupId:kotlin-stdlib:$kotlinVersion'};
    } else {
      deps = _devDeps;
    }

    final List<ResolvedArtifact> resolvedDeps;

    _logger.debug('Resolving dev deps');
    if (_devDepsBox.isEmpty) {
      resolvedDeps =
          await Future.wait([for (final dep in deps) _resolver.resolve(dep)]);
    } else {
      resolvedDeps = await Future.wait(_devDepsBox.values
          .whereNot((el) => el.jarFile.asFile().existsSync())
          .map((el) => _resolver.resolve(el.coordinate)));
    }

    _logger.debug('Downloading and caching dev deps');
    if (resolvedDeps.isNotEmpty) {
      await Future.wait([
        for (final dep in resolvedDeps) _resolver.download(dep),
        for (final dep in resolvedDeps) _resolver.downloadSources(dep),
      ]);
      await Future.wait([
        for (final dep in resolvedDeps)
          _devDepsBox.put(
              dep.coordinate,
              ExtensionLibrary(dep.coordinate, dep.cacheDir,
                  DependencyScope.provided.name, [], dep.packaging, false)),
      ]);
    }
  }

  Future<void> ensureBuildLibraries({required String kotlinVersion}) async {
    final libs = {
      '$_kotlinGroupId:kotlin-compiler-embeddable:$kotlinVersion',
      '$_kotlinGroupId:kotlin-annotation-processing-embeddable:$kotlinVersion',
      _d8Coord,
      _pgCoord,
      _manifMergerCoord,
    };

    final List<Set<ResolvedArtifact>> resolvedLibs;

    _logger.debug('Resolving tools...');
    if (_buildLibsBox.isEmpty) {
      resolvedLibs = await Future.wait([
        for (final lib in libs) _resolver.resolveTransitively(lib),
      ]);
    } else {
      final resolveFuts = <Future<Set<ResolvedArtifact>>>[];
      for (final lib in _buildLibsBox.values) {
        // If the library or any of its dependencies local file doesn't exist,
        // resolve it again.
        if (!lib.localFile.asFile().existsSync() ||
            lib.dependencies.any((el) => !el.localFile.asFile().existsSync())) {
          resolveFuts.add(_resolver.resolveTransitively(lib.coordinate));
        }
      }

      resolvedLibs = await Future.wait(resolveFuts);
    }

    _logger.debug('Downloading and caching tools...');
    if (resolvedLibs.isNotEmpty) {
      await Future.wait([
        for (final lib in resolvedLibs.flattened) _resolver.download(lib),
        ...resolvedLibs.map((el) {
          final deps = el
              .toList()
              .sublist(1)
              .map((e) => BuildLibrary(e.coordinate, e.main.localFile, []));
          return _buildLibsBox.put(el.first.coordinate,
              BuildLibrary(el.first.coordinate, el.first.main.localFile, deps));
        }),
      ]);
    }
  }
}
