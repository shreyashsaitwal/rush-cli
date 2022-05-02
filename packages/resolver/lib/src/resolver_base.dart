import 'package:resolver/src/model/artifact.dart';
import 'package:resolver/src/repositories.dart';
import 'package:resolver/src/utils.dart';

import 'fetcher.dart';
import 'model/maven/pom_model.dart';
import 'model/maven/repository.dart';

class ArtifactResolver {
  late List<Repository> _repositories;
  late String _cacheDir;

  final fetcher = ArtifactFetcher();

  ArtifactResolver({
    List<Repository> repositories = Repositories.defaultRepositories,
    String? cacheDir,
  }) {
    _repositories = repositories;
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

  void _interpolateDependencyVersion(PomModel model) {
    model.dependencies
      ..where((el) => el.version == null).forEach((dep) {
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
          throw 'Version not defined for ${dep.coordinate}';
        }

        dep.version = prop;
      })
      ..where((el) => el.version!.startsWith('\${')).forEach((dep) {
        final propName = dep.version!.substring(2, dep.version!.length - 1);

        if (model.properties.containsKey(propName)) {
          final prop = model.properties[propName];
          dep.version = prop;
        } else {
          throw 'Property $propName not found';
        }
      });
  }

  Future<ResolvedArtifact> resolvePom(String coordinate) async {
    final PomModel pom;
    final Artifact artifact;
    try {
      artifact = _artifactFor(coordinate);
      final file = await fetcher.fetchFile(artifact.pomSpec, _repositories);
      final content = file.readAsStringSync();
      pom = PomModel.fromXml(content);

      if (pom.parent != null) {
        final parent = await resolvePom(pom.parent!.coordinate);
        pom.properties.addAll(parent.pom.properties);
      }
      _interpolateDependencyVersion(pom);
    } catch (e) {
      rethrow;
    }

    return ResolvedArtifact(pom: pom, cacheDir: artifact.cacheDir);
  }

  Future<void> download(ResolvedArtifact artifact,
      {bool downloadSources = true}) async {
    // TODO: Implement hash validation of downloaded artifacts
    try {
      final futures = [
        fetcher.fetchFile(artifact.main, _repositories),
        if (downloadSources) fetcher.fetchFile(artifact.sources, _repositories),
      ];
      await Future.wait(futures);
    } catch (e) {
      rethrow;
    }
  }
}
