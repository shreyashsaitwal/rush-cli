import 'package:collection/collection.dart';
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

import '../../commands/rush_command.dart';
import '../../config/rush_yaml.dart';
import '../../resolver/artifact.dart';
import '../../resolver/resolver.dart';
import '../../services/file_service.dart';

class SyncSubCommand extends RushCommand {
  final _fs = GetIt.I<FileService>();

  @override
  String get description => 'Resolves and downloads project dependencies.';

  @override
  String get name => 'sync';

  @override
  Future<List<Artifact>> run({
    Box<Artifact>? cacheBox,
    Map<Scope, Iterable<String>> coordinates = const {},
    bool setKeysAsCoordinates = false,
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
        for (final value in entry.value)
          resolver.resolveArtifact(value, entry.key),
    ]))
        .flattened
        .toList(growable: true);

    final directDeps =
        {for (final entry in coordinates.entries) entry.value}.flattened;
    resolvedDeps = _resolveVersionConflicts(resolvedDeps, directDeps)
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
      if (setKeysAsCoordinates)
        cacheBox.putAll(Map.fromIterable(resolvedDeps, key: (el) => el.coordinate))
      else
        cacheBox.addAll(resolvedDeps),
    ]);

    return resolvedDeps;
  }

  Iterable<Artifact> _resolveVersionConflicts(
    Iterable<Artifact> resolvedArtifacts,
    Iterable<String> directDeps,
  ) {
    final sameArtifacts = resolvedArtifacts
        .groupListsBy((el) => '${el.groupId}:${el.artifactId}')
        .entries;

    final result = <Artifact>[];
    for (final entry in sameArtifacts) {
      // Filter deps that have ranges defined
      final rangedVersionDeps =
          entry.value.where((el) => el.version.range != null);

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
            print(
                'Multiple versions of ${entry.key} found. Using ${pickedArtifact.version} because its was explicit');
            // Update coordinate with ranged version to the final picked version.
            // For eg: com.example:[1.2.3] -> com.example:1.2.3
            pickedArtifact.coordinate = [
              ...pickedArtifact.coordinate.split(':').take(2),
              pickedArtifact.version.range!.upper!
            ].join(':');
            result.add(pickedArtifact);
            continue;
          }
        }

        // TODO: If there are no singleton versions pick the intersection of all ranges.
      }

      if (entry.value.length == 1) {
        result.add(entry.value.first);
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
        result.add(artifact);
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
      result.add(highestVersionDep);
    }

    return result;
  }
}
