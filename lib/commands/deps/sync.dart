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
  Future<List<Artifact>> run(
      [Box<Artifact>? depsBox, RushYaml? rushYaml]) async {
    if (depsBox == null && rushYaml == null) {
      Hive.init(p.join(_fs.dotRushDir.path));
    }
    depsBox ??= await Hive.openBox<Artifact>('deps');
    rushYaml ??= await RushYaml.load(_fs.config);

    await depsBox.clear();

    final remoteRuntimeDeps = rushYaml.runtimeDeps
        .where((el) => !el.endsWith('.jar') && !el.endsWith('.aar'));
    final remoteComptimeDeps = rushYaml.comptimeDeps
        .where((el) => !el.endsWith('.jar') && !el.endsWith('.aar'));

    final resolver = ArtifactResolver();
    var resolvedDeps = (await Future.wait([
      ...remoteRuntimeDeps
          .map((el) => resolver.resolveArtifact(el, Scope.runtime)),
      ...remoteComptimeDeps
          .map((el) => resolver.resolveArtifact(el, Scope.compile)),
    ]))
        .flattened
        .toList(growable: true);

    // Resolve version conflicts
    // FIXME: For now, we are just selecting the highest version.
    resolvedDeps = resolvedDeps
        .groupListsBy((el) => '${el.groupId}:${el.artifactId}')
        .entries
        .map((entry) {
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
            print(
                'Multiple versions of ${entry.key} found. Using ${singletonVersionDeps.first.version} because its a singleton');
            // Update coordinate with ranged version to the final picked version.
            // For eg: com.example:[1.2.3] -> com.example:1.2.3
            singletonVersionDeps.first.coordinate = [
              ...singletonVersionDeps.first.coordinate.split(':').take(2),
              singletonVersionDeps.first.version.range!.upper!.literal
            ].join(':');
            return singletonVersionDeps.first;
          }
        }

        // TODO: If there are no singleton versions pick the intersection of all ranges.
      }

      if (entry.value.length == 1) return entry.value.first;

      // If this artifact is defined as a direct dep, use that version
      final directDep = [...rushYaml!.runtimeDeps, ...rushYaml.comptimeDeps]
          .where((el) => el.split(':').take(2).join(':') == '${entry.key}:');
      if (directDep.isNotEmpty) {
        print(
            'Multiple versions of ${entry.key} found. Using ${directDep.first.split(':').last} because its a direct dep');
        return entry.value.firstWhere((el) => el.coordinate == directDep.first);
      }

      // If no version is ranged, select the highest version
      final nonRangedVersionDeps =
          entry.value.where((el) => el.version.range == null);
      final highestVersionDep = nonRangedVersionDeps
          .sorted((a, b) => a.version.compareTo(b.version))
          .first;
      print(
          'Multiple versions of ${entry.key} found. Using ${highestVersionDep.version} because its the highest');
      return highestVersionDep;
    }).toList(growable: true);

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
      depsBox.addAll(resolvedDeps),
    ]);

    return resolvedDeps;
  }
}
