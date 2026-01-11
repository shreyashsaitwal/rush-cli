/// Local Maven repository implementation.
///
/// Reads artifacts from the local Maven repository, typically at
/// `~/.m2/repository` or configured via `M2_HOME` environment variable.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'artifact_coordinate.dart';
import 'maven_metadata.dart';
import 'repository.dart';
import '../version/maven_version.dart';

/// A local Maven repository that reads from the filesystem.
///
/// By default, uses `~/.m2/repository`. This can be customized via
/// the [repositoryPath] parameter.
final class LocalRepository implements Repository {
  @override
  final String id;

  /// The path to the local repository.
  final String repositoryPath;

  /// Creates a local repository at the specified path.
  LocalRepository({
    required this.repositoryPath,
    this.id = 'local',
  });

  /// Creates a local repository at the default location.
  ///
  /// Uses `M2_HOME/repository` if `M2_HOME` is set, otherwise `~/.m2/repository`.
  factory LocalRepository.defaultLocation({String id = 'local'}) {
    final m2Home = Platform.environment['M2_HOME'];
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';

    final repoPath = m2Home != null
        ? p.join(m2Home, 'repository')
        : p.join(home, '.m2', 'repository');

    return LocalRepository(repositoryPath: repoPath, id: id);
  }

  @override
  String get location => repositoryPath;

  @override
  Future<FetchResult?> fetchPom(ArtifactCoordinate coord) async {
    final path = coord.pomPath;
    return fetchRaw(path);
  }

  @override
  Future<FetchResult?> fetchArtifact(
    ArtifactCoordinate coord, {
    String? extension,
  }) async {
    final path = coord.artifactFilePath(extension);
    return fetchRaw(path);
  }

  @override
  Future<List<MavenVersion>> listVersions(
    String groupId,
    String artifactId,
  ) async {
    // Try to read maven-metadata.xml
    final groupPath = groupId.replaceAll('.', '/');
    final metadataPath = '$groupPath/$artifactId/maven-metadata-local.xml';
    var result = await fetchRaw(metadataPath);

    // Fallback to maven-metadata.xml (without -local suffix)
    result ??= await fetchRaw('$groupPath/$artifactId/maven-metadata.xml');

    if (result != null) {
      try {
        final metadata =
            MavenMetadata.parse(result.content, path: metadataPath);
        return metadata.versions;
      } catch (_) {
        // Fall through to directory scanning
      }
    }

    // Fallback: scan directory for version folders
    final artifactDir =
        Directory(p.join(repositoryPath, groupPath, artifactId));
    if (!await artifactDir.exists()) {
      return [];
    }

    final versions = <MavenVersion>[];
    await for (final entity in artifactDir.list()) {
      if (entity is Directory) {
        final versionStr = p.basename(entity.path);
        // Check if this looks like a version (has a POM file)
        final pomFile =
            File(p.join(entity.path, '$artifactId-$versionStr.pom'));
        if (await pomFile.exists()) {
          try {
            versions.add(MavenVersion.parse(versionStr));
          } catch (_) {
            // Skip invalid version directories
          }
        }
      }
    }

    versions.sort();
    return versions;
  }

  @override
  Future<FetchResult?> fetchRaw(String path) async {
    final file = File(p.join(repositoryPath, path));

    if (!await file.exists()) {
      return null;
    }

    final stat = await file.stat();
    if (stat.size == 0) {
      return null; // Treat empty files as missing
    }

    final content = await file.readAsBytes();
    return FetchResult(
      content: Uint8List.fromList(content),
      cachedFile: file,
      fromCache: true,
    );
  }

  @override
  Future<void> close() async {
    // No resources to close for local repository
  }

  /// Saves content to the local repository.
  ///
  /// This is used when caching files downloaded from remote repositories.
  Future<File> save(String path, Uint8List content) async {
    final file = File(p.join(repositoryPath, path));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(content);
    return file;
  }

  /// Checks if a file exists in the local repository.
  Future<bool> exists(String path) async {
    final file = File(p.join(repositoryPath, path));
    return file.exists();
  }

  /// Returns the full path to a file in the repository.
  String fullPath(String relativePath) {
    return p.join(repositoryPath, relativePath);
  }
}
