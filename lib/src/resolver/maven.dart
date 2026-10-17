import 'dart:io';

import 'package:maven_resolver/maven_resolver.dart' as mvn;
import 'package:path/path.dart' as p;

import 'package:rush/src/resolver/artifact.dart';

const _defaultRepos = [
  'https://repo1.maven.org/maven2',
  'https://dl.google.com/dl/android/maven2',
];

class MavenResolver {
  MavenResolver({
    Iterable<String> repositories = const [],
    void Function(String message)? onWarning,
  })  : _onWarning = onWarning,
        _local = mvn.LocalRepository.defaultLocation() {
    _repo = mvn.CompositeRepository([
      _local,
      for (final (i, url) in {...repositories, ..._defaultRepos}.indexed)
        mvn.RemoteRepository(
          url: url,
          id: 'repo$i',
          localCache: _local,
          onWarning: onWarning,
        ),
    ]);
  }

  final void Function(String message)? _onWarning;
  final mvn.LocalRepository _local;
  late final mvn.CompositeRepository _repo;

  Future<List<Artifact>> resolve(
    Map<Scope, Iterable<String>> coordinates, {
    Set<String> exclude = const {},
  }) async {
    final directDeps = [
      for (final MapEntry(key: scope, value: coords) in coordinates.entries)
        for (final coord in coords) _dependency(coord, scope),
    ];
    if (directDeps.isEmpty) {
      return [];
    }

    final result = await mvn.DependencyResolver(
      repository: _repo,
      config: const mvn.ResolverConfig(
        scopes: {mvn.DependencyScope.compile, mvn.DependencyScope.runtime},
        failOnMissing: true,
      ),
    ).resolve(
      directDependencies: directDeps,
      exclusions: exclude.map(_exclusion).toList(),
    );

    for (final warning in result.warnings) {
      _onWarning?.call('$warning');
    }
    if (result.errors.isNotEmpty) {
      throw Exception('Unable to resolve dependencies:\n'
          '${result.errors.map((el) => '  - ${el.coordinate ?? 'dependency'}: ${el.message}').join('\n')}');
    }

    final resolved = {for (final el in result.artifacts) el.conflictKey: el};
    final graph = _withoutPomOnlyNodes(result.dependencyGraph, resolved);
    return [
      for (final el in resolved.values)
        if (!_isPomOnly(el)) _toArtifact(el, graph[el.conflictKey], resolved),
    ];
  }

  Future<List<Artifact>> download(
    Iterable<Artifact> artifacts, {
    bool withSources = false,
  }) =>
      Future.wait(artifacts.map((artifact) async {
        final coord = mvn.ArtifactCoordinate.parse(artifact.coordinate)
            .copyWith(packaging: artifact.packaging);
        if (!await _fetch(coord, artifact.artifactFile)) {
          throw Exception('Unable to find artifact file for '
              '${artifact.coordinate} in any of the available Maven '
              'repositories.');
        }

        final sources = coord.copyWith(packaging: 'jar', classifier: 'sources');
        final sourcesJar = _localPath(sources);
        final hasSources = withSources &&
            await _fetch(sources, sourcesJar).onError((_, __) => false);

        return Artifact(
          coordinate: artifact.coordinate,
          scope: artifact.scope,
          artifactFile: artifact.artifactFile,
          sourcesJar: hasSources ? sourcesJar : null,
          dependencies: artifact.dependencies,
          packaging: artifact.packaging,
        );
      }));

  Future<String?> fetchAar(String coordinate) async {
    final coord =
        mvn.ArtifactCoordinate.parse(coordinate).copyWith(packaging: 'aar');
    final path = _localPath(coord);
    return await _fetch(coord, path) ? path : null;
  }

  Future<void> close() => _repo.close();

  Artifact _toArtifact(
    mvn.ResolvedArtifact resolved,
    Set<String>? dependencyKeys,
    Map<String, mvn.ResolvedArtifact> byKey,
  ) {
    final coord = resolved.coordinate;
    final packaging = coord.packaging == 'aar' ? 'aar' : 'jar';
    return Artifact(
      coordinate: _coordinate(coord),
      scope: resolved.scope == mvn.DependencyScope.runtime
          ? Scope.runtime
          : Scope.compile,
      artifactFile: _localPath(coord.copyWith(packaging: packaging)),
      sourcesJar: null,
      dependencies: [
        for (final key in dependencyKeys ?? const <String>{})
          if (byKey[key] case final dep?) _coordinate(dep.coordinate),
      ],
      packaging: packaging,
    );
  }

  Map<String, Set<String>> _withoutPomOnlyNodes(
    Map<String, Set<String>> graph,
    Map<String, mvn.ResolvedArtifact> resolved,
  ) {
    bool isPomOnly(String key) =>
        resolved[key] != null && _isPomOnly(resolved[key]!);

    Set<String> expand(String key, Set<String> visiting) => {
          for (final child in graph[key] ?? const <String>{})
            if (!isPomOnly(child))
              child
            else if (visiting.add(child))
              ...expand(child, visiting),
        };

    return {
      for (final key in graph.keys)
        if (!isPomOnly(key)) key: expand(key, {key}),
    };
  }

  Future<bool> _fetch(mvn.ArtifactCoordinate coord, String path) async {
    final file = File(path);
    if (await file.exists()) {
      return true;
    }
    final result = await _repo.fetchArtifact(coord, extension: coord.packaging);
    if (result == null) {
      return false;
    }
    if (!await file.exists()) {
      await file.parent.create(recursive: true);
      final partial = File('$path.$pid.part');
      await partial.writeAsBytes(result.content);
      await partial.rename(path);
    }
    return true;
  }

  String _localPath(mvn.ArtifactCoordinate coord) =>
      p.join(_local.repositoryPath, coord.artifactFilePath(coord.packaging));

  static bool _isPomOnly(mvn.ResolvedArtifact artifact) =>
      artifact.coordinate.packaging == 'pom';

  static String _coordinate(mvn.ArtifactCoordinate coord) => [
        coord.groupId,
        coord.artifactId,
        if (coord.classifier case final classifier?) ...[
          coord.packaging,
          classifier
        ],
        coord.version,
      ].join(':');

  static mvn.Exclusion _exclusion(String groupAndArtifact) {
    final [groupId, artifactId] = groupAndArtifact.split(':');
    return mvn.Exclusion(groupId: groupId, artifactId: artifactId);
  }

  static mvn.Dependency _dependency(String coord, Scope scope) {
    final c = mvn.ArtifactCoordinate.parse(coord);
    return mvn.Dependency(
      groupId: c.groupId,
      artifactId: c.artifactId,
      version: c.version,
      type: c.packaging,
      classifier: c.classifier,
      scope: scope == Scope.runtime
          ? mvn.DependencyScope.runtime
          : mvn.DependencyScope.compile,
    );
  }
}
