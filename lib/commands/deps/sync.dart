import 'dart:io';

import 'package:collection/collection.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:resolver/resolver.dart';
import 'package:rush_cli/commands/build/hive_adapters/remote_dep.dart';

import '../../commands/rush_command.dart';
import '../../models/rush_yaml/rush_yaml.dart';
import '../../services/file_service.dart';
import '../../utils/cmd_utils.dart';
import '../../templates/intellij_files.dart';
import '../build/utils/build_utils.dart';

class SyncSubCommand extends RushCommand {
  final FileService _fs;

  SyncSubCommand(this._fs);

  @override
  String get description =>
      'Syncs the remote dependencies of the current project.';

  @override
  String get name => 'sync';

  @override
  Future<Set<RemoteDep>> run({bool isHiveInit = false}) async {
    // TODO: Console output
    final rushYaml = CmdUtils.loadRushYaml(_fs.cwd);

    final remoteDeps = rushYaml.deps?.where((el) => el.isRemote) ?? [];
    if (remoteDeps.isEmpty) return {};

    final toResolve = {for (var el in remoteDeps) el.value: el.scope};

    // TODO: Add ability to add extra repositories and change cache dir
    final resolver = ArtifactResolver();

    final resolvedArtifacts = (await Future.wait({
      for (final el in toResolve.entries)
        _resolveDep(resolver, el.key, el.value)
    }))
        .flattened
        .toSet();

    // TODO: Handle the artifacts that are already available as dev-deps
    // TODO: Handle ignored deps.
    // TODO: Handle different versions of of same artifacts

    // Download all the resolved artifacts
    await Future.wait([
      // TODO: Remove the unimplemented error
      ...resolvedArtifacts.map(
          (el) => resolver.download(el, onError: () => UnimplementedError())),
      ...resolvedArtifacts.map((el) => resolver.downloadSources(el)),
    ]);

    print('Updating library files');
    for (final artifact in resolvedArtifacts) {
      _updateLibXml(artifact);
    }

    return await _storeCache(resolvedArtifacts, remoteDeps.toSet(), isHiveInit);
  }

  Future<Set<ResolvedArtifact>> _resolveDep(
    ArtifactResolver resolver,
    String coordinate,
    DependencyScope scope,
  ) async {
    print('Resolving $coordinate');
    final resolved = await resolver.resolve(coordinate, scope);

    // Remove the unnecessary dependencies
    resolved.pom.dependencies = List.of(resolved.pom.dependencies)
      ..removeWhere((el) => el.optional)
      ..removeWhere((el) {
        if (scope == DependencyScope.compile) {
          return el.scope != DependencyScope.compile;
        }

        if (scope == DependencyScope.runtime) {
          return !(el.scope == DependencyScope.compile ||
              el.scope == DependencyScope.runtime);
        }

        // Any other scope is not possible because the resolver will only resolve
        // runtime or compile scoped dependencies.
        return true;
      });

    final depResolveFutures = <Future<Set<ResolvedArtifact>>>{};
    for (final el in resolved.pom.dependencies) {
      depResolveFutures.add(_resolveDep(resolver, el.coordinate, el.scope));
    }
    final resolvedDeps = (await Future.wait(depResolveFutures)).flattened;

    return {resolved, ...resolvedDeps};
  }

  Future<Set<RemoteDep>> _storeCache(Set<ResolvedArtifact> resolvedArtifacts,
      Set<DepEntry> remoteDeps, bool isHiveInit) async {
    if (!isHiveInit) {
      Hive
        ..init(p.join(_fs.cwd, '.rush'))
        ..registerAdapter(RemoteDepAdapter());
    }

    final indexBox = await Hive.openBox<RemoteDep>('index');

    if (indexBox.isNotEmpty) {
      await indexBox.clear();
    }

    final index = {
      for (final el in resolvedArtifacts)
        RemoteDep(
          el.coordinate,
          el.cacheDir,
          el.scope.name,
          el.pom.dependencies.map((el) => el.coordinate).toList(),
          el.packaging,
          remoteDeps.any(
              (dep) => dep.value == el.coordinate && dep.scope == el.scope),
        )
    };

    try {
      await indexBox.addAll(index.toList());
    } catch (e) {
      print(e);
      rethrow;
    }

    return index;
  }

  void _updateLibXml(ResolvedArtifact artifact) {
    final classes = <String>[];

    if (artifact.packaging == 'aar') {
      final outputDir = Directory(p.withoutExtension(artifact.main.localFile))
        ..createSync(recursive: true);

      final classesJarFile = File(p.join(outputDir.path, 'classes.jar'));
      final manifestXml = File(p.join(outputDir.path, 'AndroidManifest.xml'));

      if (!classesJarFile.existsSync()) {
        BuildUtils.unzip(artifact.main.localFile, outputDir.path);
      }

      classes
        ..add(classesJarFile.path)
        ..add(manifestXml.path);
    } else {
      classes.add(artifact.main.localFile);
    }

    final xmlFileName =
        artifact.coordinate.replaceAll(':', '-') + '-' + artifact.packaging;

    CmdUtils.writeFile(
      p.join(_fs.cwd, '.idea', 'libraries', '$xmlFileName.xml'),
      getLibXml(xmlFileName, classes, artifact.sources.localFile),
    );
  }
}
