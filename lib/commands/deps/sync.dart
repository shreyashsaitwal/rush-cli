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
      Hive
        ..init(p.join(_fs.cwd, '.rush'))
        ..registerAdapter(ArtifactAdapter())
        ..registerAdapter(ScopeAdapter());
    }

    rushYaml ??= await RushYaml.load(_fs.cwd);
    final remoteDeps = rushYaml.deps.where((el) => el.isRemote);

    final resolver = ArtifactResolver();
    final resolvedArtifacts = await Future.wait([
      for (final dep in remoteDeps)
        resolver.resolveArtifact(dep.value, dep.scope)
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
