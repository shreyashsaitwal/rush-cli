import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:rush_cli/resolver/artifact.dart';

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
    if (!isHiveInit) {
      Hive.init(p.join(_fs.cwd, '.rush'));
    }

    rushYaml ??= await RushYaml.load(_fs.cwd);
    final remoteRuntimeDeps = rushYaml.runtimeDeps.where((el) => !el.endsWith('.jar') && !el.endsWith('.aar'));
    final remoteComptimeDeps = rushYaml.comptimeDeps.where((el) => !el.endsWith('.jar') && !el.endsWith('.aar'));

    final resolver = ArtifactResolver();
    final resolvedArtifacts = await Future.wait([
      for (final dep in remoteRuntimeDeps)
        resolver.resolveArtifact(dep, Scope.runtime),
      for (final dep in remoteComptimeDeps)
        resolver.resolveArtifact(dep, Scope.compile)
    ]);

    await Future.wait([
      for (final artifact in resolvedArtifacts)
        resolver.downloadArtifact(artifact),
      for (final artifact in resolvedArtifacts)
        resolver.downloadSourceJar(artifact),
    ]);

    final depBox = await Hive.openBox<Artifact>('deps');
    await depBox.clear();
    await depBox.addAll(resolvedArtifacts);

    return resolvedArtifacts;
  }
}
