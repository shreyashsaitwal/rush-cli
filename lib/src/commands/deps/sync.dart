import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:collection/collection.dart';
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

import 'package:rush/src/commands/build/utils.dart';
import 'package:rush/src/commands/create/templates/eclipse_files.dart';
import 'package:rush/src/commands/create/templates/intellij_files.dart';
import 'package:rush/src/config/config.dart';
import 'package:rush/src/resolver/artifact.dart';
import 'package:rush/src/resolver/maven.dart';
import 'package:rush/src/services/ai2_runtime.dart';
import 'package:rush/src/services/file_service.dart';
import 'package:rush/src/services/lib_service.dart';
import 'package:rush/src/services/logger.dart';
import 'package:rush/src/utils/constants.dart';
import 'package:rush/src/utils/file_extension.dart';
import 'package:rush/src/utils/error_message.dart';

const _buildToolCoords = [
  r8Coord,
  pgCoord,
  coreLibraryCoord,
  coreLibraryConfigCoord,
  ...manifMergerAndDeps,
];

class SyncSubCommand extends Command<int> {
  static final _fs = GetIt.I<FileService>();
  static final _lgr = GetIt.I<Logger>();

  SyncSubCommand() {
    argParser
      ..addFlag('dev-deps', abbr: 'd', help: 'Syncs only the dev-dependencies.')
      ..addFlag('project-deps',
          abbr: 'p', help: 'Syncs only the project dependencies.')
      ..addFlag('force',
          abbr: 'f',
          help:
              'Forcefully syncs all the dependencies even if they are up-to-date.');
  }

  @override
  String get description => 'Syncs dev and project dependencies.';

  @override
  String get name => 'sync';

  @override
  Future<int> run({String title = 'Initializing'}) async {
    _lgr.startTask(title);

    final onlyDevDeps = (argResults?['dev-deps'] ?? false) as bool;
    final onlyExtDeps = (argResults?['project-deps'] ?? false) as bool;
    final useForce = (argResults?['force'] ?? false) as bool;

    final config = await Config.load(_fs.configFile, _lgr);
    if (config == null && !onlyDevDeps) {
      _lgr.warn('Not in a Rush project, only dev-dependencies will be synced.');
    }

    await GetIt.I.isReady<LibService>();
    final libService = GetIt.I<LibService>();

    // Clear all the cache if force is used.
    if (useForce) {
      if (!onlyExtDeps) {
        await libService.updateBuildLibs((box) => box.clear());
      }
      if (!onlyDevDeps && config != null) {
        await libService.extensionDepsBox!.clear();
      }
    }

    final toolsToFetch = _missingBuildTools(config, libService);

    // Stop the init task
    _lgr.stopTask();

    final installRuntime = useForce || !Ai2Runtime.isInstalled;
    if (!onlyExtDeps && (installRuntime || toolsToFetch.isNotEmpty)) {
      _lgr.startTask('Syncing dev-dependencies');
      try {
        await Future.wait([
          if (installRuntime) Ai2Runtime.install(),
          if (toolsToFetch.isNotEmpty)
            libService.updateBuildLibs((box) => sync(
                  cacheBox: box,
                  coordinates: {Scope.compile: toolsToFetch},
                )),
        ]);
      } catch (e, s) {
        _lgr
          ..err(errorMessage(e))
          ..dbg(s.toString())
          ..stopTask(false);
        return 1;
      }
      _lgr.stopTask();
    } else if (!onlyExtDeps) {
      _lgr
        ..startTask('Syncing dev-dependencies')
        ..stopTask();
    }

    // Exit if this is not a Rush project.
    if (config == null) {
      return 0;
    }

    final ai2ProvidedDepArtifacts = await libService.providedDependencies(null);

    Hive.init(_fs.dotRushDir.path);
    final timestampBox = await Hive.openLazyBox<DateTime>(timestampBoxName);

    final extensionDeps = await libService.extensionDependencies(config);
    final needSync = await _doProjectDepsNeedSync(timestampBox, extensionDeps);
    if (useForce || (!onlyDevDeps && needSync)) {
      _lgr.startTask('Syncing project dependencies');

      final extDepCoords = config.dependencies
          .where((el) => !el.endsWith('.jar') && !el.endsWith('.aar'));
      final extProvidedDepCoords = config.providedDependencies
          .where((el) => !el.endsWith('.jar') && !el.endsWith('.aar'));

      try {
        await sync(
          cacheBox: libService.extensionDepsBox!,
          coordinates: {Scope.provided: extProvidedDepCoords},
          repositories: config.repositories,
          downloadSources: true,
        );

        final inEveryApp = await libService.dependenciesInEveryApp(config);
        await sync(
          cacheBox: libService.extensionDepsBox!,
          coordinates: {Scope.compile: extDepCoords},
          repositories: config.repositories,
          providedArtifacts: inEveryApp,
          excluded: config.excludedLibraries,
          placedLibraries:
              config.libraries.keys.whereNot(config.dependencies.contains),
          downloadSources: true,
        );
        await timestampBox.put(configTimestampKey, DateTime.now());
      } catch (_) {
        _lgr.stopTask(false);
        return 1;
      }
      await _removeRogueDeps({...extDepCoords, ...extProvidedDepCoords},
          libService.extensionDepsBox!);
      _lgr.stopTask();
    } else if (!onlyDevDeps) {
      _lgr
        ..startTask('Syncing project dependencies')
        ..stopTask();
    }

    _lgr.startTask('Adding resolved dependencies to your IDE\'s lib index');

    try {
      final extensionDeps = await libService.extensionDependencies(config,
          includeProjectProvidedDeps: true);
      await BuildUtils.extractAars(
        extensionDeps
            .where((el) => el.artifactFile.endsWith('.aar'))
            .where((el) =>
                !el.classesJar.asFile().existsSync() ||
                !_fs
                    .resourceFromExtractedAar(
                        el.artifactFile, 'AndroidManifest.xml')
                    .existsSync())
            .map((el) => el.artifactFile),
      );

      await _updateIntellijLibIndex(ai2ProvidedDepArtifacts, extensionDeps);
      await _updateEclipseClasspath(ai2ProvidedDepArtifacts, extensionDeps);
    } catch (_) {
      _lgr.stopTask(false);
      return 1;
    }

    _lgr.stopTask();
    return 0;
  }

  static Set<String> _missingBuildTools(Config? config, LibService libService) {
    final ktVersion = config?.kotlin.compilerVersion ?? defaultKtVersion;
    final toolsCoord = _buildToolCoords +
        [
          '$kotlinGroupId:kotlin-compiler-embeddable:$ktVersion',
          '$kotlinGroupId:kotlin-annotation-processing-embeddable:$ktVersion',
          if (_fs.resDir.existsSync()) aapt2Coord,
        ];

    // Build tools to be resolved
    final toolsToFetch = <String>{};
    final buildLibArtifacts = libService.buildLibArtifacts();

    // Add every un-cached tool to the fetch list.
    for (final coord in toolsCoord) {
      if (buildLibArtifacts.none((el) => el.coordinate == coord)) {
        toolsToFetch.add(coord);
      }
    }

    // Add every non existent tool to the fetch list. This can happen when the
    // said tool was deleted or the local Maven repo location was changed.
    toolsToFetch.addAll(
      buildLibArtifacts
          .where((el) => !el.artifactFile.asFile().existsSync())
          .map((el) => el.coordinate)
          .where((el) => el.trim().isNotEmpty),
    );
    return toolsToFetch;
  }

  static Future<bool> needsSync(Config config, LibService libService) async {
    if (!Ai2Runtime.isInstalled ||
        _missingBuildTools(config, libService).isNotEmpty) {
      return true;
    }
    Hive.init(_fs.dotRushDir.path);
    final timestampBox = await Hive.openLazyBox<DateTime>(timestampBoxName);
    return _doProjectDepsNeedSync(
        timestampBox, await libService.extensionDependencies(config));
  }

  static Future<bool> _doProjectDepsNeedSync(
      LazyBox<DateTime> timestampBox, List<Artifact> projectDeps) async {
    // Re-fetch deps if they are outdated, ie, if the config file is modified
    // or if the dep artifacts are missing
    final configFileModified = (await timestampBox.get(configTimestampKey))
            ?.isBefore(_fs.configFile.lastModifiedSync()) ??
        true;
    final isAnyDepMissing = projectDeps.any((el) =>
        !el.artifactFile.endsWith('.pom') &&
        !el.artifactFile.asFile().existsSync());
    return configFileModified || isAnyDepMissing;
  }

  static Future<Iterable<Artifact>> _removeRogueDeps(
      Iterable<String> primaryArtifactCoords, LazyBox<Artifact> cache,
      [bool putInCache = true]) async {
    final actualDeps = <Artifact>{};

    for (final el in primaryArtifactCoords) {
      final artifact = await cache.get(el);
      if (artifact == null) {
        continue;
      }

      actualDeps.add(artifact);

      final depArtifacts = await Future.wait([
        for (final dep in artifact.dependencies) cache.get(dep),
      ]);
      actualDeps.addAll(depArtifacts.whereNotNull());

      final transDepArtifacts = await Future.wait([
        for (final dep in depArtifacts.whereNotNull())
          _removeRogueDeps(dep.dependencies, cache, false),
      ]);
      actualDeps.addAll(transDepArtifacts.whereNotNull().flattened);
    }

    if (putInCache) {
      await cache.clear();
      await cache.putAll({
        for (final el in actualDeps) el.coordinate: el,
      });
    }
    return actualDeps;
  }

  Future<List<Artifact>> sync({
    required LazyBox<Artifact> cacheBox,
    required Map<Scope, Iterable<String>> coordinates,
    Iterable<String> repositories = const [],
    Iterable<Artifact> providedArtifacts = const [],
    Set<String> excluded = const {},
    Iterable<String> placedLibraries = const [],
    bool downloadSources = false,
  }) async {
    _lgr.info('Resolving ${coordinates.values.flattened.length} artifacts...');
    final resolver = MavenResolver(
      repositories: repositories,
      onWarning: (msg) => _lgr.dbg(msg),
    );

    try {
      final directCoords = coordinates.values.flattened.toSet();
      final provided = {
        for (final el in providedArtifacts)
          if (el.isMavenArtifact && !directCoords.contains(el.coordinate))
            el.groupAndArtifactId: el,
      };

      if (provided.isNotEmpty || placedLibraries.isNotEmpty) {
        final unexcluded = await resolver.resolve(coordinates);
        _warnAboutOutdatedProvidedDeps(unexcluded, provided);
        _warnAboutUnmatchedLibraries(placedLibraries, unexcluded);
      }

      _lgr.info('Downloading resolved artifacts...');
      final resolvedDeps = await resolver.download(
        await resolver
            .resolve(coordinates, exclude: {...provided.keys, ...excluded}),
        withSources: downloadSources,
      );
      await cacheBox.putAll({
        for (final dep in resolvedDeps) dep.coordinate: dep,
      });
      return resolvedDeps;
    } catch (e, s) {
      _lgr
        ..err(errorMessage(e))
        ..dbg(s.toString());
      rethrow;
    } finally {
      await resolver.close();
    }
  }

  void _warnAboutOutdatedProvidedDeps(
    Iterable<Artifact> required,
    Map<String, Artifact> providedByKey,
  ) {
    for (final dep in required) {
      final provided = providedByKey[dep.groupAndArtifactId];
      if (provided == null) continue;
      if (dep.version.compareTo(provided.version) > 0) {
        _lgr.warn('${dep.coordinate} is required, but App Inventor provides '
            'an older version (${provided.coordinate}) which will be used '
            'instead. This may cause errors at runtime.');
      } else {
        _lgr.dbg('Provided alternative found for ${dep.coordinate}: '
            '${provided.coordinate}');
      }
    }
  }

  void _warnAboutUnmatchedLibraries(
      Iterable<String> placedLibraries, Iterable<Artifact> resolved) {
    final libraries = resolved.map((el) => el.groupAndArtifactId).toSet();
    for (final library in placedLibraries.whereNot(libraries.contains)) {
      _lgr.warn('`$library` in `libraries` matches no library in the '
          'dependencies. Check its spelling.');
    }
  }

  Future<void> _updateEclipseClasspath(
      Iterable<Artifact> providedDeps, Iterable<Artifact> extensionDeps) async {
    if (!await p.join(_fs.cwd, '.project').asFile().exists()) {
      return;
    }

    final classesJars = [
      ...providedDeps.map((el) => el.classesJar).whereNotNull(),
      ...extensionDeps.map((el) => el.classesJar).whereNotNull(),
    ];
    final sourcesJars = [
      ...providedDeps.map((el) => el.sourcesJar).whereNotNull(),
      ...extensionDeps.map((el) => el.sourcesJar).whereNotNull(),
    ];
    await p
        .join(_fs.cwd, '.classpath')
        .asFile()
        .writeAsString(dotClasspath(classesJars, sourcesJars));
  }

  Future<void> _updateIntellijLibIndex(
      Iterable<Artifact> providedDeps, Iterable<Artifact> extensionDeps) async {
    final ideaDir = p.join(_fs.cwd, '.idea').asDir();
    if (!await ideaDir.exists()) {
      return;
    }

    final providedDepsLibXml =
        p.join(_fs.cwd, '.idea', 'libraries', 'provided-deps.xml').asFile(true);
    await providedDepsLibXml.writeAsString(
      ijProvidedDepsXml(
        providedDeps.map((el) => el.classesJar).whereNotNull(),
        providedDeps.map((el) => el.sourcesJar).whereNotNull(),
      ),
    );

    await p
        .join(_fs.cwd, '.idea', 'libraries', 'local-deps.xml')
        .asFile()
        .writeAsString(ijLocalDepsXml);

    final libNames = <String>['provided-deps', 'local-deps'];
    for (final lib in extensionDeps) {
      final fileName = lib.coordinate.replaceAll(RegExp(r'(:|\.)'), '_');
      final xml =
          p.join(_fs.cwd, '.idea', 'libraries', '$fileName.xml').asFile(true);

      await xml.writeAsString('''
<component name="libraryTable">
  <library name="${lib.coordinate}">
    <CLASSES>
      <root url="jar://${lib.classesJar}!/" />
    </CLASSES>
    <SOURCES>
      ${lib.sourcesJar != null ? '<root url="jar://${lib.sourcesJar!}!/" />' : ''}
    </SOURCES>
    <JAVADOC />
  </library>
</component>
''');

      libNames.add(lib.coordinate);
    }

    final imlXml = p
        .join(_fs.cwd, '.idea')
        .asDir()
        .listSync()
        .firstWhereOrNull((el) => el is File && p.extension(el.path) == '.iml');
    if (imlXml == null) {
      throw Exception('Unable to find project\'s .iml file in .idea directory');
    }

    await imlXml.path.asFile().writeAsString(ijImlXml(libNames));
  }
}
