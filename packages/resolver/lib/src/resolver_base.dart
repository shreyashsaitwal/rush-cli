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
          version: parts[2].replaceAll(RegExp(r'(\[|\])'), ''),
          cacheDir: _cacheDir);
    } else if (parts.length == 4) {
      return Artifact(
          groupId: parts[0],
          artifactId: parts[1],
          // parts[2] is the packaging of the artifact. We extract it from pom.xml
          version: parts[3].replaceAll(RegExp(r'(\[|\])'), ''),
          cacheDir: _cacheDir);
    } else {
      throw 'Invalid artifact coordinate: $coordinate';
    }
  }

  void _interpolateDependencyVersion(PomModel model) {
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
          throw 'Unable to figure which version of ${dep.groupId}:${dep.artifactId} to use';
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
          throw 'Property $propName not found';
        }
      });
  }

  String? _findVersionInProperties(PomModel model, Dependency dep) {
    final String prop;

    if (model.properties.containsKey('${dep.artifactId}.version')) {
      prop = model.properties['${dep.artifactId}.version'];
    } else if (model.properties.containsKey('version.${dep.artifactId}')) {
      prop = model.properties['version.${dep.artifactId}'];
    } else if (model.properties.containsKey('${dep.groupId}.version')) {
      prop = model.properties['${dep.groupId}.version'];
    } else if (model.properties.containsKey('${dep.groupId}.version')) {
      prop = model.properties['version.${dep.groupId}'];
    } else {
      return null;
    }
    return prop;
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
      final content = file.readAsStringSync();
      pom = PomModel.fromXml(content);

      if (pom.parent != null) {
        final parent = await resolve(pom.parent!.coordinate, scope);
        pom.parent!.dependencies =
            pom.parent!.dependencies + parent.pom.dependencies;
        pom.properties.addAll(parent.pom.properties);
      }
      _interpolateDependencyVersion(pom);
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
