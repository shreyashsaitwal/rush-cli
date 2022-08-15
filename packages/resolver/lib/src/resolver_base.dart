import 'package:collection/collection.dart';
import 'package:resolver/src/model/artifact.dart';
import 'package:resolver/src/repositories.dart';
import 'package:resolver/src/utils.dart';

import 'fetcher.dart';
import 'model/maven/pom_model.dart';
import 'model/maven/repository.dart';

class ArtifactResolver {
  late Set<Repository> _repositories;
  late String _cacheDir;

  final _fetcher = ArtifactFetcher();

  ArtifactResolver({
    List<Repository>? repositories,
    String? cacheDir,
  }) {
    _repositories = repositories != null
        ? {...repositories.toSet(), ...Repositories.defaultRepositories}
        : Repositories.defaultRepositories;
    _cacheDir = cacheDir ?? Utils.defaultCacheDir;
  }

  Artifact _artifactFor(String coordinate) {
    final parts = coordinate.split(':');
    if (parts.length == 3) {
      return Artifact(
          groupId: parts[0],
          artifactId: parts[1],
          version: parts[2],
          cacheDir: _cacheDir);
    } else if (parts.length == 4) {
      return Artifact(
          groupId: parts[0],
          artifactId: parts[1],
          // parts[2] is the packaging of the artifact. We extract it from pom.xml
          version: parts[3],
          cacheDir: _cacheDir);
    } else {
      throw 'Invalid artifact coordinate: $coordinate';
    }
  }

  void _interpolateDependencyVersions(PomModel model) {
    model.dependencies
      ..where((el) => el.version == null).forEach((dep) {
        dep.version = _findVersionInProperties(model, dep);

        if (dep.version != null) {
          return;
        }

        if (model.parent != null) {
          dep.version = _findVersionFromParentsDeps(
              model.parent!, dep.groupId, dep.groupId);
        } else {
          throw '''
Unable to interpolate dependency version for ${dep.coordinate}.
This is not supposed to happen!!! Please report this to the maintainer of Rush.''';
        }
      })
      ..whereNot((el) => el.version == null)
          .where((el) => el.version!.startsWith('\${'))
          .forEach((dep) {
        final propName = dep.version!.substring(2, dep.version!.length - 1);

        if (model.properties.containsKey(propName)) {
          final prop = model.properties[propName];
          dep.version = prop;
        } else {
          throw '''
Unable to interpolate dependency version for ${dep.coordinate}.
This is not supposed to happen!!! Please report this to the maintainer of Rush.''';
        }
      })
      ..forEach((el) {
        el.version = el.version!.replaceAll(RegExp(r'(\[|\])'), '');
      });
  }

  String? _findVersionInProperties(PomModel model, Dependency dep) {
    // This is not an exhaustive list of possible property names.
    // TODO: Research and add more.
    final possiblePropertyNames = [
      '${dep.artifactId}.version',
      'version.${dep.artifactId}',
      '${dep.groupId}.version',
      'version.${dep.groupId}',
    ];

    for (final name in possiblePropertyNames) {
      if (model.properties.containsKey(name)) {
        return model.properties[name];
      }
    }

    return null;
  }

  String? _findVersionFromParentsDeps(
      Parent parent, String groupId, String artifactId) {
    final matchingDeps = parent.dependencies
        .where((el) => el.groupId == groupId && el.artifactId == artifactId);

    if (matchingDeps.isEmpty) {
      return null;
    }

    return matchingDeps.first.version;
  }

  Future<ResolvedArtifact> resolve(
      String coordinate, DependencyScope? scope) async {
    final PomModel pom;
    final Artifact artifact;
    try {
      artifact = _artifactFor(coordinate);
      final file = await _fetcher.fetchFile(artifact.pomSpec, _repositories);
      final content = await file.readAsString();
      pom = PomModel.fromXml(content);

      if (pom.parent != null) {
        // The <parent> tag doesn't contain the dependency info, therefore, we
        // need to resolve the parent and add the dependencies manually.
        final resolvedParent = await resolve(pom.parent!.coordinate, scope);
        pom.parent!.dependencies =
            pom.parent!.dependencies + resolvedParent.pom.dependencies;

        // ...same goes for the <properties> tag
        pom.properties.addAll(resolvedParent.pom.properties);
      }

      // Sometimes, the dependency version are defined as properties, either in
      // the current pom, or in parent. We need to interpolate them.
      // If the versions are not defined as properties, we need to inherit the
      // version from parent's dependencies.
      _interpolateDependencyVersions(pom);
    } catch (e, s) {
      print(e);
      print(s);
      rethrow;
    }

    return ResolvedArtifact(
        pom: pom,
        scope: scope ?? DependencyScope.compile,
        cacheDir: artifact.cacheDir);
  }

  Future<void> download(ResolvedArtifact artifact, {Function? onError}) async {
    try {
      await _fetcher.fetchFile(artifact.main, _repositories);
    } catch (e) {
      if (onError != null) {
        onError(e);
      } else {
        rethrow;
      }
    }
  }

  Future<void> downloadSources(ResolvedArtifact artifact,
      {Function? onError}) async {
    try {
      await _fetcher.fetchFile(artifact.sources, _repositories);
    } catch (e) {
      if (onError != null) {
        onError(e);
      }
    }
  }
}
