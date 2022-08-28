import 'package:collection/collection.dart';
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/resolver/artifact.dart';
import 'package:rush_cli/utils/file_extension.dart';

import '../../commands/rush_command.dart';
import '../../config/rush_yaml.dart';
import '../../resolver/resolver.dart';
import '../../services/file_service.dart';

class SyncSubCommand extends RushCommand {
  final FileService _fs = GetIt.I<FileService>();

  @override
  String get description =>
      'Syncs the remote dependencies of the current project.';

  @override
  String get name => 'sync';

  @override
  Future<List<Artifact>> run(
      {RushYaml? rushYaml, bool isHiveInit = false}) async {
    final time = DateTime.now();
    if (!isHiveInit) {
      // We don't need to register the Artifact and other adapters here because
      // they are already registered in the [LibService], which is a singleton
      // and get's intialized before any command runs.
      Hive.init(p.join(_fs.cwd, '.rush'));
    }
    final depsBox = await Hive.openBox<Artifact>('deps');

    // TODO: This is probably not the best way to check if sync is needed.
    // Return early if every dependency in the box exists.
    final everyDepExists =
        depsBox.values.every((el) => el.classesJar.asFile().existsSync());
    if (depsBox.isNotEmpty && everyDepExists) {
      return depsBox.values.toList();
    }
    await depsBox.clear();

    rushYaml ??= await RushYaml.load(_fs.cwd);
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
      if (entry.value.length == 1) return entry.value.first;
      final sorted =
          entry.value.sorted((a, b) => a.version.compareTo(b.version));
      return sorted.last;
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
