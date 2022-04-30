import 'dart:io';

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

  Future<ResolvedArtifact> resolvePom(String coordinate) async {
    final PomModel pom;
    final Artifact artifact;
    try {
      artifact = _artifactFor(coordinate);
      final file = await fetcher.fetchFile(artifact.pomSpec, _repositories);
      final content = file.readAsStringSync();
      pom = PomModel.fromXml(content);
    } catch (e) {
      rethrow;
    }
    return ResolvedArtifact(pom: pom, cacheDir: artifact.cacheDir);
  }

  Future<void> download(ResolvedArtifact artifact, {bool downloadSources = true}) async {
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
