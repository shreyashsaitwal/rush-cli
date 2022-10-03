import 'dart:io';

import 'package:collection/collection.dart';
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/src/commands/create/templates/eclipse_files.dart';
import 'package:rush_cli/src/commands/create/templates/intellij_files.dart';
import 'package:rush_cli/src/utils/file_extension.dart';
import 'package:xrange/xrange.dart';

import 'package:rush_cli/src/command_runner.dart';
import 'package:rush_cli/src/config/config.dart';
import 'package:rush_cli/src/resolver/artifact.dart';
import 'package:rush_cli/src/resolver/resolver.dart';
import 'package:rush_cli/src/services/file_service.dart';
import 'package:rush_cli/src/services/libs_service.dart';
import 'package:rush_cli/src/services/logger.dart';
import 'package:rush_cli/src/utils/constants.dart';

const _providedDepsCoords = <String>[
  'io.github.shreyashsaitwal.rush:annotations:$annotationProcVersion',
  'io.github.shreyashsaitwal.rush:runtime:$ai2RuntimeVersion',
];

const _buildToolCoords = [
  rushApCoord,
  r8Coord,
  pgCoord,
  desugarCoord,
  ...manifMergerAndDeps,
];

class SyncSubCommand extends RushCommand {
  final _fs = GetIt.I<FileService>();
  final _lgr = GetIt.I<Logger>();

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
  Future<int> run() async {
    _lgr.startTask('Initializing');

    final onlyDev = argResults!['dev-deps'] as bool;
    final onlyProject = argResults!['project-deps'] as bool;
    final useForce = argResults!['force'] as bool;

    final config = await Config.load(_fs.configFile, _lgr);
    if (config == null && !onlyDev) {
      _lgr.warn('Not in a Rush project, only dev-dependencies will be synced.');
    }

    await GetIt.I.isReady<LibService>();
    final libService = GetIt.I<LibService>();

    final ktVersion = config?.kotlin?.compilerVersion ?? defaultKtVersion;
    final toolsCoord = _buildToolCoords +
        [
          '$kotlinGroupId:kotlin-compiler-embeddable:$ktVersion',
          '$kotlinGroupId:kotlin-annotation-processing-embeddable:$ktVersion',
        ];

    // Dev deps to be resolved
    final providedDepsToFetch = <String>{};
    final toolsToFetch = <String>{};

    final providedDepsFromCache = await libService.providedDepArtifacts();
    final buildToolsFromCache = await libService.buildLibArtifacts();

    // Add every un-cached dev dep to fetch list.
    for (final coord in _providedDepsCoords) {
      if (useForce ||
          providedDepsFromCache.none((el) => el.coordinate == coord)) {
        providedDepsToFetch.add(coord);
      }
    }
    for (final coord in toolsCoord) {
      if (useForce ||
          buildToolsFromCache.none((el) => el.coordinate == coord)) {
        toolsToFetch.add(coord);
      }
    }

    // Add every non existent dev dep to the fetch list. This can happen when
    // the said dev was deleted or the local Maven repo location was changed.
    providedDepsToFetch.addAll(
      providedDepsFromCache
          .where((el) => useForce || !el.artifactFile.asFile().existsSync())
          .map((el) => el.coordinate),
    );
    toolsToFetch.addAll(
      buildToolsFromCache
          .where((el) => useForce || !el.artifactFile.asFile().existsSync())
          .map((el) => el.coordinate),
    );

    // Stop the init task
    _lgr.stopTask();

    if (!onlyProject &&
        (providedDepsToFetch.isNotEmpty || toolsToFetch.isNotEmpty)) {
      _lgr.startTask('Syncing dev-dependencies');
      try {
        await Future.wait([
          sync(
            libCacheBox: libService.devDepsBox,
            coordinates: {Scope.compile: providedDepsToFetch},
            downloadSources: true,
          ),
          sync(
            libCacheBox: libService.buildLibsBox,
            coordinates: {Scope.runtime: toolsToFetch},
          ),
        ]);
      } catch (_) {
        _lgr.stopTask(false);
        return 1;
      }
      _lgr.stopTask();
    } else if (!onlyProject) {
      _lgr
        ..startTask('Syncing dev-dependencies')
        ..stopTask();
    }

    // Exit if this is not a Rush project.
    if (config == null) {
      return 0;
    }

    Hive.init(_fs.dotRushDir.path);
    final timestampBox = await Hive.openLazyBox<DateTime>(timestampBoxName);
    final projectDepsBox = await Hive.openLazyBox<Artifact>(projectDepsBoxName);

    // Re-fetch deps if they are outdated, ie, if the config file is modified
    // or if the dep artifacts are missing
    final configFileModified = (await timestampBox.get(configTimestampKey))
            ?.isBefore(_fs.configFile.lastModifiedSync()) ??
        true;
    final isAnyDepMissing = (await libService.projectRemoteDepArtifacts()).any(
        (el) =>
            !el.artifactFile.endsWith('.pom') &&
            !el.artifactFile.asFile().existsSync());

    if (!onlyDev && (configFileModified || isAnyDepMissing || useForce)) {
      _lgr.startTask('Syncing project dependencies');

      final projectDepCoords = {
        Scope.runtime: config.runtimeDeps
            .whereNot((el) => el.endsWith('.jar') || el.endsWith('.aar')),
        Scope.compile: config.comptimeDeps
            .whereNot((el) => el.endsWith('.jar') || el.endsWith('.aar')),
      };

      try {
        await sync(
          libCacheBox: projectDepsBox,
          coordinates: projectDepCoords,
          repositories: config.repositories,
          devDepArtifacts: await libService.providedDepArtifacts(),
          downloadSources: true,
        );
        await timestampBox.put(configTimestampKey, DateTime.now());
      } catch (_) {
        _lgr.stopTask(false);
        return 1;
      }
      _lgr.stopTask();
    } else {
      _lgr
        ..startTask('Syncing project dependencies')
        ..stopTask();
    }

    _lgr.startTask('Adding resolved dependencies to your IDE\'s lib index');
    try {
      final providedDeps = await libService.providedDepArtifacts();
      final projectDeps = await libService.projectRemoteDepArtifacts();
      _updateIjLibIndex(providedDeps, projectDeps);
      _updateEclipseClasspath(providedDeps, projectDeps);
    } catch (_) {
      _lgr.stopTask(false);
      return 1;
    }
    _lgr.stopTask();
    return 0;
  }

  Future<List<Artifact>> sync({
    required LazyBox<Artifact> libCacheBox,
    required Map<Scope, Iterable<String>> coordinates,
    Iterable<String> repositories = const [],
    Iterable<Artifact> devDepArtifacts = const [],
    bool downloadSources = false,
  }) async {
    _lgr.info('Resolving ${coordinates.values.flattened.length} artifacts...');
    final resolver = ArtifactResolver(repos: repositories.toSet());

    List<Artifact> resolvedDeps = [];
    try {
      resolvedDeps = (await Future.wait([
        for (final entry in coordinates.entries)
          for (final coord in entry.value)
            resolver.resolveArtifact(coord, entry.key),
      ]))
          .flattened
          .toList(growable: true);
    } catch (e, s) {
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
      resolvedDeps = (await _resolveVersionConflicts(
              resolvedDeps, directDeps, resolver, devDepArtifacts))
          .toList(growable: true);
    } catch (e) {
      resolver.closeHttpClient();
      rethrow;
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
        libCacheBox.putAll({
          for (final dep in resolvedDeps) dep.coordinate: dep,
        }),
      ]);
    } catch (e) {
      resolver.closeHttpClient();
      rethrow;
    }

    resolver.closeHttpClient();
    return resolvedDeps;
  }

  Future<Iterable<Artifact>> _resolveVersionConflicts(
    Iterable<Artifact> resolvedArtifacts,
    Iterable<String> directDeps,
    ArtifactResolver resolver,
    Iterable<Artifact> devDepArtifacts,
  ) async {
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

      final providedAlternative =
          await _providedAlternative(entry.key, devDepArtifacts);
      final scope = entry.value.any((el) => el.scope == Scope.runtime)
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

            // Ignore this artifact if it is provided by App Inventor.
            if (providedAlternative != null &&
                pickedArtifact.coordinate == providedAlternative.coordinate) {
              _lgr.dbg('Provided alternative found for ${entry.key}');
              continue;
            }

            _lgr.dbg(
                '${entry.value.length} versions for ${entry.key} found; using ${pickedArtifact.version} because its a direct dep');
            result.add(pickedArtifact..scope = scope);
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

        if (providedAlternative != null &&
            intersection.contains(providedAlternative.version)) {
          _lgr.dbg('Provided alternative found for ${entry.key}');
          continue;
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
          newCoordsToReResolve.putIfAbsent(pickedCoordinate, () => scope);
          continue;
        }

        result.add(pickedArtifacts.first..scope = scope);
        continue;
      }

      if (entry.value.length == 1) {
        result.add(entry.value.first..scope = scope);
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
        result.add(artifact..scope = scope);
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
      result.add(highestVersionDep..scope = scope);
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
        devDepArtifacts,
      );
    }

    return result;
  }

  Future<Artifact?> _providedAlternative(
      String artifactIdent, Iterable<Artifact> devDeps) async {
    for (final val in devDeps) {
      if (val.coordinate.startsWith(artifactIdent)) {
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
      Iterable<Artifact> providedDeps, Iterable<Artifact> projectDeps) {
    final dotClasspathFile = p.join(_fs.cwd, '.classpath').asFile();
    if (!dotClasspathFile.existsSync()) {
      return;
    }

    final classesJars = [
      ...providedDeps.map((el) => el.classesJar).whereNotNull(),
      ...projectDeps.map((el) => el.classesJar).whereNotNull(),
    ];
    final sourcesJars = [
      ...providedDeps.map((el) => el.sourcesJar).whereNotNull(),
      ...projectDeps.map((el) => el.sourcesJar).whereNotNull(),
    ];
    dotClasspathFile.writeAsStringSync(dotClasspath(classesJars, sourcesJars));
  }

  void _updateIjLibIndex(
      Iterable<Artifact> providedDeps, Iterable<Artifact> projectDeps) {
    final ideaDir = p.join(_fs.cwd, '.idea').asDir();
    if (!ideaDir.existsSync()) {
      return;
    }

    final devDepsLibXml =
        p.join(_fs.cwd, '.idea', 'libraries', 'dev-deps.xml').asFile(true);
    devDepsLibXml.writeAsStringSync(
      ijDevDepsXml(
        providedDeps.map((el) => el.classesJar).whereNotNull(),
        providedDeps
            .whereNot((element) => element.sourcesJar == null)
            .map((el) => el.sourcesJar!),
      ),
    );

    final libNames = <String>['deps', 'dev-deps'];
    for (final lib in projectDeps) {
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
