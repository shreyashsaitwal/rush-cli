
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:resolver/resolver.dart';

import '../build/hive_adapters/library_box.dart';
import '../../commands/rush_command.dart';
import '../../config/rush_yaml.dart';
import '../../services/file_service.dart';

class SyncSubCommand extends RushCommand {
  final FileService _fs = GetIt.I<FileService>();

  @override
  String get description =>
      'Syncs the remote dependencies of the current project.';

  @override
  String get name => 'sync';

  @override
  Future<Set<ExtensionLibrary>> run(
      {RushYaml? rushYaml, bool isHiveInit = false}) async {
    rushYaml ??= await RushYaml.load(_fs.cwd);
    if (!isHiveInit) {
      Hive
        ..init(p.join(_fs.cwd, '.rush'))
        ..registerAdapter(ExtensionLibraryAdapter());
    }
    final resolver = ArtifactResolver();

    final remoteDeps = rushYaml.deps.where((el) => el.isRemote);
    final resolved = await Future.wait([
      for (final dep in remoteDeps) resolver.resolveTransitively(dep.value)
    ]);

    await Future.wait([
      for (final libSet in resolved)
        for (final lib in libSet) resolver.download(lib),
      for (final libSet in resolved)
        for (final lib in libSet) resolver.downloadSources(lib),
    ]);

    final extensionLibs = resolved.map((el) {
      final deps = el.toList().sublist(1);
      return ExtensionLibrary(
        el.first.coordinate,
        el.first.cacheDir,
        DependencyScope.runtime.name,
        deps.map((e) => e.coordinate).toList(),
        el.first.packaging,
        true,
      );
    });

    final depBox = await Hive.openBox<ExtensionLibrary>('deps');
    await depBox.addAll(extensionLibs);
    
    return extensionLibs.toSet();
  }
}
