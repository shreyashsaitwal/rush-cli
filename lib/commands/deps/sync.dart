import 'package:collection/collection.dart';
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:xrange/xrange.dart';

import '../../commands/rush_command.dart';
import '../../config/rush_yaml.dart';
import '../../resolver/artifact.dart';
import '../../resolver/resolver.dart';
import '../../services/file_service.dart';
import '../../services/libs_service.dart';

class SyncSubCommand extends RushCommand {
  final _fs = GetIt.I<FileService>();
  final _libService = GetIt.I<LibService>();

  @override
  String get description => 'Resolves and downloads project dependencies.';

  @override
  String get name => 'sync';

  @override
  Future<int> run() async {
    await sync();
    return 0;
  }

  Future<List<Artifact>> sync({
    Box<Artifact>? cacheBox,
    Map<Scope, Iterable<String>> coordinates = const {},
    bool saveCoordinatesAsKeys = false,
  }) async {
    // Initialize all the parameters if this was invoked as a subcommand.
    if (cacheBox == null) {
      Hive.init(p.join(_fs.dotRushDir.path));
      final config = await RushYaml.load(_fs.configFile);
      if (coordinates.isEmpty) {
        coordinates = {
          Scope.runtime: config.runtimeDeps
              .whereNot((el) => el.endsWith('.jar') || el.endsWith('.aar')),
          Scope.compile: config.comptimeDeps
              .whereNot((el) => el.endsWith('.jar') || el.endsWith('.aar')),
        };
      }
    }

    cacheBox ??= await Hive.openBox<Artifact>('deps');
    await cacheBox.clear();

    final resolver = ArtifactResolver();
    var resolvedDeps = (await Future.wait([
      for (final entry in coordinates.entries)
        for (final coord in entry.value)
          resolver.resolveArtifact(coord, entry.key),
    ]))
        .flattened
        .toList(growable: true);

    final directDeps =
        {for (final entry in coordinates.entries) entry.value}.flattened;
    resolvedDeps =
        (await _resolveVersionConflicts(resolvedDeps, directDeps, resolver))
            .toList(growable: true);

    // Update the versions of transitive dependencies once the version conflicts
    // are resolved.
    resolvedDeps = resolvedDeps.map((dep) {
      dep.dependencies = List.of(dep.dependencies).map((el) {
        final artifact = resolvedDeps.firstWhere((art) =>
            '${art.groupId}:${art.artifactId}' ==
            el.split(':').take(2).join(':'));
        return artifact.coordinate;
      }).toList();
      return dep;
    }).toList();

    // Download the artifacts and then add them to the cache
    await Future.wait([
      for (final dep in resolvedDeps) resolver.downloadArtifact(dep),
      if (saveCoordinatesAsKeys)
        cacheBox
            .putAll(Map.fromIterable(resolvedDeps, key: (el) => el.coordinate))
      else
        cacheBox.addAll(resolvedDeps),
    ]);

    return resolvedDeps;
  }

  Future<Iterable<Artifact>> _resolveVersionConflicts(
    Iterable<Artifact> resolvedArtifacts,
    Iterable<String> directDeps,
    ArtifactResolver resolver,
  ) async {
    final sameArtifacts = resolvedArtifacts
        .groupListsBy((el) => '${el.groupId}:${el.artifactId}')
        .entries;

    final result = <Artifact>[];
    final newCoordsToReResolve = <String, Scope>{};

    for (final entry in sameArtifacts) {
      // Filter deps that have ranges defined
      final rangedVersionDeps =
          entry.value.where((el) => el.version.range != null).toSet();
      final providedAlternative = _providedAlternative(entry.key);
      final scope = entry.value.any((el) => el.scope == Scope.runtime)
          ? Scope.runtime
          : Scope.compile;

      if (rangedVersionDeps.isNotEmpty) {
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
              continue;
            }

            print(
                'Multiple versions of ${entry.key} found. Using ${pickedArtifact.version} because its was explicit');
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
      // Note: when this method if called from the build command, the coordinates
      // are the direct deps.
      final directDep = {
        for (final coord in directDeps)
          if (coord.split(':').take(2).join(':') == '${entry.key}:') coord
      };
      if (directDep.isNotEmpty) {
        print(
            'Multiple versions of ${entry.key} found. Using ${directDep.first.split(':').last} because its a direct dep');
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
      print(
          'Multiple versions of ${entry.key} found. Using ${highestVersionDep.version} because its the highest');
      result.add(highestVersionDep..scope = scope);
    }

    // Resolve any new coordinates that were added to the `newArtifactsToReResolve`
    if (newCoordsToReResolve.isNotEmpty) {
      final newResolved = await Future.wait([
        for (final entry in newCoordsToReResolve.entries)
          resolver.resolveArtifact(entry.key, entry.value)
      ]);
      return await _resolveVersionConflicts(
        [...newResolved.flattened, ...result],
        directDeps,
        resolver,
      );
    }

    return result;
  }

  Artifact? _providedAlternative(String artifactIdent) {
    final devDepBox = _libService.devDepsBox;
    for (final val in devDepBox.values) {
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
}
