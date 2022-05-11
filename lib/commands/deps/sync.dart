import 'dart:io';

import 'package:collection/collection.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:resolver/resolver.dart';
import 'package:rush_cli/commands/build/hive_adapters/remote_dep_index.dart';

import '../../commands/rush_command.dart';
import '../../services/file_service.dart';
import '../../utils/cmd_utils.dart';
import '../../templates/intellij_files.dart';
import '../build/utils/build_utils.dart';

class DepsSyncCommand extends RushCommand {
  final FileService _fs;

  DepsSyncCommand(this._fs);

  @override
  String get description =>
      'Syncs the remote dependencies of the current project.';

  @override
  String get name => 'sync';

  @override
  Future<Set<RemoteDepIndex>> run({bool updateIdeaFiles = true}) async {
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
    // TODO: Handle different versions of of same artifacts

    // Download all the resolved artifacts
    await Future.wait([
      // TODO: Remove the unimplemented error
      ...resolvedArtifacts.map(
          (el) => resolver.download(el, onError: () => UnimplementedError())),
      ...resolvedArtifacts.map((el) => resolver.downloadSources(el)),
    ]);

    if (updateIdeaFiles) {
      print('Updating library files');
      for (final artifact in resolvedArtifacts) {
        _updateLibXml(artifact);
      }
    }

    return await _storeCache(resolvedArtifacts);
  }

  Future<Set<ResolvedArtifact>> _resolveDep(
    ArtifactResolver resolver,
    String coordinate,
    DependencyScope scope,
  ) async {
    // TODO: Handle "ignore" deps. 

    print('Resolving $coordinate');
    final resolved = await resolver.resolve(coordinate, scope);

    // Only take the deps if they are:
    // * not optional
    // * of compile scope when the current scope is compile
    // * of runtime / compile scope when the current scope is runtime
    final deps =
        resolved.pom.dependencies.whereNot((el) => el.optional).where((el) {
      if (scope == DependencyScope.compile) {
        return el.scope == DependencyScope.compile;
      } else if (scope == DependencyScope.runtime) {
        return el.scope == DependencyScope.compile ||
            el.scope == DependencyScope.runtime;
      }

      return false;
    });

    final depResolveFutures = <Future<Set<ResolvedArtifact>>>{};
    for (final el in deps) {
      depResolveFutures.add(_resolveDep(resolver, el.coordinate, el.scope));
    }
    final resolvedDeps = (await Future.wait(depResolveFutures)).flattened;

    return {resolved, ...resolvedDeps};
  }

  Future<Set<RemoteDepIndex>> _storeCache(
      Set<ResolvedArtifact> resolvedArtifacts) async {
    final indexBox = await Hive.openBox<RemoteDepIndex>('index');

    if (indexBox.isNotEmpty) {
      await indexBox.clear();
    }

    final index = {
      for (final el in resolvedArtifacts)
        RemoteDepIndex(
          el.coordinate,
          el.cacheDir,
          el.scope.name,
          el.pom.dependencies.map((el) => el.coordinate).toList(),
          el.packaging,
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
