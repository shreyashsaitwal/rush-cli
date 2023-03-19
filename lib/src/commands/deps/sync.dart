import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:collection/collection.dart';
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:xrange/xrange.dart';

import 'package:rush_cli/src/commands/build/utils.dart';
import 'package:rush_cli/src/commands/create/templates/eclipse_files.dart';
import 'package:rush_cli/src/commands/create/templates/intellij_files.dart';
import 'package:rush_cli/src/config/config.dart';
import 'package:rush_cli/src/resolver/artifact.dart';
import 'package:rush_cli/src/resolver/resolver.dart';
import 'package:rush_cli/src/services/file_service.dart';
import 'package:rush_cli/src/services/lib_service.dart';
import 'package:rush_cli/src/services/logger.dart';
import 'package:rush_cli/src/utils/constants.dart';
import 'package:rush_cli/src/utils/file_extension.dart';

const ai2RuntimeCoord =
    'io.github.shreyashsaitwal.rush:runtime:$ai2RuntimeVersion';
const _buildToolCoords = [
  rushApCoord,
  r8Coord,
  pgCoord,
  desugarCoord,
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
        await libService.providedDepsBox.clear();
        await libService.buildLibsBox.clear();
      }
      if (!onlyDevDeps && config != null) {
        await libService.extensionDepsBox.clear();
      }
    }

    final ktVersion = config?.kotlin.compilerVersion ?? defaultKtVersion;
    final toolsCoord = _buildToolCoords +
        [
          '$kotlinGroupId:kotlin-compiler-embeddable:$ktVersion',
          '$kotlinGroupId:kotlin-annotation-processing-embeddable:$ktVersion',
        ];

    // Dev deps to be resolved
    final providedDepsToFetch = <String>{};
    final toolsToFetch = <String>{};

    var providedDepArtifacts = await libService.providedDependencies();
    var buildLibArtifacts = await libService.buildLibArtifacts();

    // Add every un-cached dev dep to fetch list.
    if (providedDepArtifacts.none((el) => el.coordinate == ai2RuntimeCoord)) {
      providedDepsToFetch.add(ai2RuntimeCoord);
    }
    for (final coord in toolsCoord) {
      if (buildLibArtifacts.none((el) => el.coordinate == coord)) {
        toolsToFetch.add(coord);
      }
    }

    // Add every non existent dev dep to the fetch list. This can happen when
    // the said dep was deleted or the local Maven repo location was changed.
    providedDepsToFetch.addAll(
      providedDepArtifacts
          .where((el) => !el.artifactFile.asFile().existsSync())
          .map((el) => el.coordinate)
          .where((el) => el.trim().isNotEmpty),
    );
    toolsToFetch.addAll(
      buildLibArtifacts
          .where((el) => !el.artifactFile.asFile().existsSync())
          .map((el) => el.coordinate)
          .where((el) => el.trim().isNotEmpty),
    );

    // Stop the init task
    _lgr.stopTask();

    if (!onlyExtDeps &&
        (providedDepsToFetch.isNotEmpty || toolsToFetch.isNotEmpty)) {
      _lgr.startTask('Syncing dev-dependencies');
      try {
        await Future.wait([
          sync(
            cacheBox: libService.providedDepsBox,
            coordinates: {Scope.runtime: providedDepsToFetch},
            downloadSources: true,
            excludeCoordinates: ['com.google.android:android:2.1.2'],
          ),
          sync(
            cacheBox: libService.buildLibsBox,
            coordinates: {Scope.runtime: toolsToFetch},
          ),
        ]);
      } catch (_) {
        _lgr.stopTask(false);
        return 1;
      }

      await Future.wait([
        _removeRogueDeps([
          ai2RuntimeCoord,
          'android-$androidPlatformSdkVersion.jar',
          'kawa-1.11-modified.jar',
          'physicaloid-library.jar'
        ], libService.providedDepsBox),
      ]);
      _lgr.stopTask();
    } else if (!onlyExtDeps) {
      _lgr
        ..startTask('Syncing dev-dependencies')
        ..stopTask();
    }
    BuildUtils.extractAars(
      providedDepArtifacts
          .where((el) => el.artifactFile.endsWith('.aar'))
          .where((el) =>
              !el.classesJar.asFile().existsSync() ||
              !BuildUtils.resourceFromExtractedAar(
                      el.artifactFile, 'AndroidManifest.xml')
                  .existsSync())
          .map((el) => el.artifactFile),
    );

    // Exit if this is not a Rush project.
    if (config == null) {
      return 0;
    }

    // Update the vars after syncing dev deps.
    providedDepArtifacts = await libService.providedDependencies();
    buildLibArtifacts = await libService.buildLibArtifacts();

    Hive.init(_fs.dotRushDir.path);
    final timestampBox = await Hive.openLazyBox<DateTime>(timestampBoxName);

    final extensionDeps = await libService.extensionDependencies(config);
    final needSync = await extensionDepsNeedSync(timestampBox, extensionDeps);
    if (useForce || (!onlyDevDeps && needSync)) {
      _lgr.startTask('Syncing project dependencies');

      final extDepCoords = {
        Scope.runtime: config.runtimeDeps
            .where((el) => !el.endsWith('.jar') && !el.endsWith('.aar')),
        Scope.compile: config.comptimeDeps
            .where((el) => !el.endsWith('.jar') && !el.endsWith('.aar')),
      };

      try {
        await sync(
          cacheBox: libService.extensionDepsBox,
          coordinates: extDepCoords,
          repositories: config.repositories,
          providedArtifacts: providedDepArtifacts,
          downloadSources: true,
          removeProvided: true,
        );
        await timestampBox.put(configTimestampKey, DateTime.now());
      } catch (_) {
        _lgr.stopTask(false);
        return 1;
      }
      await _removeRogueDeps(
          extDepCoords.values.flattened, libService.extensionDepsBox);
      _lgr.stopTask();
    } else if (!onlyDevDeps) {
      _lgr
        ..startTask('Syncing project dependencies')
        ..stopTask();
    }

    _lgr.startTask('Adding resolved dependencies to your IDE\'s lib index');

    try {
      final extensionDeps = await libService.extensionDependencies(config);
      BuildUtils.extractAars(
        extensionDeps
            .where((el) => el.artifactFile.endsWith('.aar'))
            .where((el) =>
                !el.classesJar.asFile().existsSync() ||
                !BuildUtils.resourceFromExtractedAar(
                        el.artifactFile, 'AndroidManifest.xml')
                    .existsSync())
            .map((el) => el.artifactFile),
      );

      _updateIntellijLibIndex(providedDepArtifacts, extensionDeps);
      _updateEclipseClasspath(providedDepArtifacts, extensionDeps);
    } catch (_) {
      _lgr.stopTask(false);
      return 1;
    }

    _lgr.stopTask();
    return 0;
  }

  static Future<bool> extensionDepsNeedSync(LazyBox<DateTime> timestampBox,
      List<Artifact> extensionDependencies) async {
    // Re-fetch deps if they are outdated, ie, if the config file is modified
    // or if the dep artifacts are missing
    final configFileModified = (await timestampBox.get(configTimestampKey))
            ?.isBefore(_fs.configFile.lastModifiedSync()) ??
        true;
    final isAnyDepMissing = extensionDependencies.any((el) =>
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
    bool downloadSources = false,
    bool removeProvided = false,
    List<String> excludeCoordinates = const [],
  }) async {
    _lgr.info('Resolving ${coordinates.values.flattened.length} artifacts...');
    final resolver = ArtifactResolver(repos: repositories.toSet());

    List<Artifact> resolvedDeps = [];
    try {
      resolvedDeps = (await Future.wait([
        for (final entry in coordinates.entries)
          for (final coord in entry.value)
            resolver.resolveArtifact(coord, entry.key,
                exclude: excludeCoordinates),
      ]))
          .flattened
          .toList(growable: true);
    } catch (e, s) {
      resolver.closeHttpConn();
      _lgr
        ..err(e.toString())
        ..dbg(s.toString());
      rethrow;
    }

    final directDeps =
        {for (final entry in coordinates.entries) entry.value}.flattened;

    try {
      // Resolve version comflicts
      _lgr.info('Resolving version conflicts...');
      resolvedDeps =
          (await _resolveVersionConflicts(resolvedDeps, directDeps, resolver))
              .toList(growable: true);
    } catch (e) {
      resolver.closeHttpConn();
      rethrow;
    }

    // When resolving extension deps, remove provided deps from dependencies
    // field and add them to the providedDependencies field of each artifact.
    if (removeProvided) {
      final providedDeps = <String>{};
      resolvedDeps.removeWhere((el) {
        final provided = _providedAlternative(
          '${el.groupId}:${el.artifactId}',
          providedArtifacts,
          coordinates.values.flattened,
        );
        if (provided != null) {
          providedDeps.add(el.coordinate);
          _lgr.dbg(
              'Provided alternative found for ${el.coordinate}: ${provided.coordinate}');
          return true;
        }
        return false;
      });
      for (final el in resolvedDeps) {
        el.dependencies.removeWhere((coord) => providedDeps.contains(coord));
      }
    }

    // Update the versions of transitive dependencies once the version conflicts
    // are resolved.
    resolvedDeps = resolvedDeps.map((dep) {
      dep.dependencies = List.of(dep.dependencies)
          .map((el) {
            final artifact = resolvedDeps.firstWhereOrNull((art) =>
                '${art.groupId}:${art.artifactId}' ==
                el.split(':').take(2).join(':'));
            return artifact?.coordinate;
          })
          .whereNotNull()
          .toList();
      return dep;
    }).toList();

    // Download the artifacts and then add them to the cache
    _lgr.info('Downloading resolved artifacts...');
    try {
      await Future.wait([
        for (final dep in resolvedDeps) resolver.downloadArtifact(dep),
        if (downloadSources)
          for (final dep in resolvedDeps) resolver.downloadSourcesJar(dep),
        cacheBox.putAll({
          for (final dep in resolvedDeps) dep.coordinate: dep,
        }),
      ]);
    } catch (e) {
      resolver.closeHttpConn();
      rethrow;
    }

    resolver.closeHttpConn();
    return resolvedDeps;
  }

  Future<Iterable<Artifact>> _resolveVersionConflicts(
      Iterable<Artifact> resolvedArtifacts,
      Iterable<String> directDeps,
      ArtifactResolver resolver) async {
    final sameArtifacts = resolvedArtifacts
        .groupListsBy((el) => '${el.groupId}:${el.artifactId}')
        .entries;

    if (!sameArtifacts.any((el) => el.value.length > 1)) {
      return resolvedArtifacts;
    }

    final result = <Artifact>[];
    final newCoordsToReResolve = <String, Scope>{};

    for (final entry in sameArtifacts) {
      // Filter deps that have ranges defined
      final rangedVersionDeps =
          entry.value.where((el) => el.version.range != null).toSet();

      final updatedScope = entry.value.any((el) => el.scope == Scope.runtime)
          ? Scope.runtime
          : Scope.compile;

      if (rangedVersionDeps.isNotEmpty) {
        _lgr.dbg('Total ranged: ${rangedVersionDeps.length}');

        // A singleton range is a range that allows only one exact value.
        // Eg: [1.2.3]
        final singletonVersionDeps = rangedVersionDeps
            .where((el) => el.version.range!.isSingleton)
            .toSet();

        // In ranged version deps, select the singleton version if there exist
        // "only one" and if it doesn't conflict with other ranges. Otherwise
        // it's an error.
        if (singletonVersionDeps.isNotEmpty) {
          // The singleton must be a part of each range for it to not conflict.
          final everyRangeContainsSingleton = rangedVersionDeps.every((el) => el
              .version.range!
              .encloses(singletonVersionDeps.first.version.range!));

          if (singletonVersionDeps.length > 1 || !everyRangeContainsSingleton) {
            throw Exception(
                'Unable to resolve version conflict for ${entry.key}:\n'
                'multiple versions found: ${singletonVersionDeps.map((e) => e.version.range).join(', ')}');
          } else {
            final pickedArtifact = singletonVersionDeps.first;
            // Update coordinate with ranged version to the final picked version.
            // For eg: com.example:[1.2.3] -> com.example:1.2.3
            pickedArtifact.coordinate = [
              ...pickedArtifact.coordinate.split(':').take(2),
              pickedArtifact.version.range!.upper!
            ].join(':');

            _lgr.dbg(
                '${entry.value.length} versions for ${entry.key} found; using ${pickedArtifact.version} because its a direct dep');
            result.add(pickedArtifact..scope = updatedScope);
            continue;
          }
        }

        // If there's no singleton version, then we need to first find the
        // intersection of all the ranges and then pick a version that falls
        // in it.
        final intersection =
            _intersection(rangedVersionDeps.map((e) => e.version.range!));
        if (intersection == null) {
          throw Exception(
              'Unable to resolve version conflict for ${entry.key}:\n'
              'multiple versions found: ${rangedVersionDeps.map((e) => e.version.range).join(', ')}');
        }

        Version? pickedVersion;
        if (intersection.upperBounded) {
          pickedVersion = intersection.upper!;
        } else if (intersection.lowerBounded) {
          pickedVersion = intersection.lower!;
        } else {
          // If the intersection is all infinity, then iterate through all the
          // ranges and pick any version - upper or lower - that we find first.
          for (final dep in rangedVersionDeps) {
            if (dep.version.range!.upperBounded) {
              pickedVersion = dep.version.range!.upper!;
              break;
            } else if (dep.version.range!.lowerBounded) {
              pickedVersion = dep.version.range!.lower!;
              break;
            }
          }
          if (pickedVersion == null) {
            throw Exception(
                'Unable to resolve version conflict for ${entry.key}:\n'
                'multiple versions found: ${rangedVersionDeps.map((e) => e.version.range).join(', ')}');
          }
        }

        final pickedCoordinate = '${entry.key}:$pickedVersion';
        final pickedArtifacts = rangedVersionDeps
            .where((el) => el.coordinate == pickedCoordinate)
            .toList(growable: true);

        // If `pickedArtifacts` is empty, then it means that this version of
        // this artifact wasn't resolved. We store such artifacts and there deps
        // in the `newArtifactsToReResolve` list and resolve them later.
        if (pickedArtifacts.isEmpty) {
          newCoordsToReResolve.putIfAbsent(
              pickedCoordinate, () => updatedScope);
          continue;
        }

        result.add(pickedArtifacts.first..scope = updatedScope);
        continue;
      }

      if (entry.value.length == 1) {
        result.add(entry.value.first..scope = updatedScope);
        continue;
      }

      // If this artifact is defined as a direct dep, use that version.
      // Note: when this method is called from the build command, the `coordinates`
      // are the direct deps.
      final directDep = {
        for (final coord in directDeps)
          if (coord.split(':').take(2).join(':') == '${entry.key}:') coord
      };
      if (directDep.isNotEmpty) {
        _lgr.dbg(
            '${entry.value.length} versions for ${entry.key} found; using ${directDep.first.split(':').last} because its a direct dep');
        final artifact =
            entry.value.firstWhere((el) => el.coordinate == directDep.first);
        result.add(artifact..scope = updatedScope);
        continue;
      }

      // If no version is ranged, select the highest version
      final nonRangedVersionDeps =
          entry.value.where((el) => el.version.range == null);
      final highestVersionDep = nonRangedVersionDeps
          .sorted((a, b) => a.version.compareTo(b.version))
          .first;
      _lgr.dbg(
          '${entry.value.length} versions for ${entry.key} found; using ${highestVersionDep.version} because its the highest');
      result.add(highestVersionDep..scope = updatedScope);
    }

    // Resolve any new coordinates that were added to the `newArtifactsToReResolve`
    if (newCoordsToReResolve.isNotEmpty) {
      _lgr.dbg(
          'Fetching new resolved versions for ${newCoordsToReResolve.keys.length} coordinates');

      List<List<Artifact>> resolvedArtifactsNew;
      try {
        resolvedArtifactsNew = await Future.wait([
          for (final entry in newCoordsToReResolve.entries)
            resolver.resolveArtifact(entry.key, entry.value),
        ]);
      } catch (e, s) {
        _lgr
          ..err(e.toString())
          ..dbg(s.toString());
        rethrow;
      }

      return await _resolveVersionConflicts(
        [...resolvedArtifactsNew.flattened, ...result],
        directDeps,
        resolver,
      );
    }

    return result;
  }

  static Artifact? _providedAlternative(
    String artifactIdent,
    Iterable<Artifact> providedDepArtifacts,
    Iterable<String> primaryArtifactCoords,
  ) {
    for (final val in providedDepArtifacts) {
      if (val.coordinate.startsWith(artifactIdent) &&
          !primaryArtifactCoords.contains(val.coordinate)) {
        return val;
      }
    }
    return null;
  }

  Range<T>? _intersection<T extends Comparable<T>>(Iterable<Range<T>> ranges) {
    var result = ranges.first;
    var previous = ranges.first;
    for (final range in ranges) {
      if (!range.connectedTo(previous)) {
        return null;
      } else {
        result = Range<T>.encloseAll([previous, range]);
      }
      previous = range;
    }
    return result;
  }

  void _updateEclipseClasspath(
      Iterable<Artifact> providedDeps, Iterable<Artifact> extensionDeps) {
    final dotClasspathFile = p.join(_fs.cwd, '.classpath').asFile();
    if (!dotClasspathFile.existsSync()) {
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
    dotClasspathFile.writeAsStringSync(dotClasspath(classesJars, sourcesJars));
  }

  void _updateIntellijLibIndex(
      Iterable<Artifact> providedDeps, Iterable<Artifact> extensionDeps) {
    final ideaDir = p.join(_fs.cwd, '.idea').asDir();
    if (!ideaDir.existsSync()) {
      return;
    }

    final providedDepsLibXml =
        p.join(_fs.cwd, '.idea', 'libraries', 'provided-deps.xml').asFile(true);
    providedDepsLibXml.writeAsStringSync(
      ijProvidedDepsXml(
        providedDeps.map((el) => el.classesJar).whereNotNull(),
        providedDeps.map((el) => el.sourcesJar).whereNotNull(),
      ),
    );

    final libNames = <String>['deps', 'provided-deps'];
    for (final lib in extensionDeps) {
      final fileName = lib.coordinate.replaceAll(RegExp(r'(:|\.)'), '_');
      final xml =
          p.join(_fs.cwd, '.idea', 'libraries', '$fileName.xml').asFile(true);

      xml.writeAsStringSync('''
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

    imlXml.path.asFile().writeAsStringSync(ijImlXml(libNames));
  }
}
