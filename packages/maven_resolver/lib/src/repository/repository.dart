/// Abstract repository interface for Maven artifact resolution.
///
/// This defines the contract for local and remote repositories to fetch
/// POMs, artifacts, and metadata.
library;

import 'dart:io';
import 'dart:typed_data';

import 'artifact_coordinate.dart';
import 'repository_exception.dart';
import '../version/maven_version.dart';

/// Checksum verification policy.
///
/// Controls behavior when checksum files are missing or verification fails.
enum ChecksumPolicy {
  /// Fail if checksum is missing or verification fails.
  fail,

  /// Log a warning but continue with the file.
  warn,

  /// Silently continue with the file.
  ignore,
}

/// Update policy for SNAPSHOT versions.
///
/// Controls how often to check for updated SNAPSHOTs.
enum UpdatePolicy {
  /// Always check for updates.
  always,

  /// Check once per day.
  daily,

  /// Never check for updates.
  never,
}

/// The result of fetching a file from a repository.
final class FetchResult {
  /// The fetched content.
  final Uint8List content;

  /// The file path if saved to local cache.
  final File? cachedFile;

  /// Whether this was served from local cache.
  final bool fromCache;

  const FetchResult({
    required this.content,
    this.cachedFile,
    this.fromCache = false,
  });
}

/// Abstract interface for Maven repositories.
///
/// Implementations include:
/// - [LocalRepository] for ~/.m2/repository
/// - [RemoteRepository] for HTTP/HTTPS Maven repositories
abstract interface class Repository {
  /// A unique identifier for this repository.
  String get id;

  /// The base URL or path of this repository.
  String get location;

  /// Fetches the POM file for the given artifact coordinate.
  ///
  /// Returns null if the artifact doesn't exist in this repository.
  /// Throws [RepositoryException] subclasses on errors.
  Future<FetchResult?> fetchPom(ArtifactCoordinate coord);

  /// Fetches the artifact file for the given coordinate.
  ///
  /// The [extension] parameter overrides the packaging type when needed.
  /// Returns null if the artifact doesn't exist in this repository.
  /// Throws [RepositoryException] subclasses on errors.
  Future<FetchResult?> fetchArtifact(
    ArtifactCoordinate coord, {
    String? extension,
  });

  /// Lists all available versions for an artifact.
  ///
  /// Returns an empty list if the artifact doesn't exist.
  /// Throws [RepositoryException] subclasses on errors.
  Future<List<MavenVersion>> listVersions(String groupId, String artifactId);

  /// Fetches raw content at the given path.
  ///
  /// The path is relative to the repository root.
  /// Returns null if the file doesn't exist.
  Future<FetchResult?> fetchRaw(String path);

  /// Closes any resources held by this repository.
  ///
  /// After calling close, the repository should not be used.
  Future<void> close();
}

/// A composite repository that searches multiple repositories in order.
final class CompositeRepository implements Repository {
  /// The repositories to search, in order.
  final List<Repository> repositories;

  @override
  final String id;

  /// Creates a composite repository from the given list.
  ///
  /// Repositories are searched in order; the first one to return a result wins.
  CompositeRepository(this.repositories, {this.id = 'composite'});

  @override
  String get location => repositories.map((r) => r.location).join(', ');

  @override
  Future<FetchResult?> fetchPom(ArtifactCoordinate coord) async {
    for (final repo in repositories) {
      final result = await repo.fetchPom(coord);
      if (result != null) return result;
    }
    return null;
  }

  @override
  Future<FetchResult?> fetchArtifact(
    ArtifactCoordinate coord, {
    String? extension,
  }) async {
    for (final repo in repositories) {
      final result = await repo.fetchArtifact(coord, extension: extension);
      if (result != null) return result;
    }
    return null;
  }

  @override
  Future<List<MavenVersion>> listVersions(
    String groupId,
    String artifactId,
  ) async {
    final allVersions = <MavenVersion>{};
    for (final repo in repositories) {
      final versions = await repo.listVersions(groupId, artifactId);
      allVersions.addAll(versions);
    }
    final sorted = allVersions.toList()..sort();
    return sorted;
  }

  @override
  Future<FetchResult?> fetchRaw(String path) async {
    for (final repo in repositories) {
      final result = await repo.fetchRaw(path);
      if (result != null) return result;
    }
    return null;
  }

  @override
  Future<void> close() async {
    for (final repo in repositories) {
      await repo.close();
    }
  }
}
