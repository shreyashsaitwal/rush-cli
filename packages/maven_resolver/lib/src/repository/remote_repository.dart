/// Remote Maven repository implementation.
///
/// Fetches artifacts from HTTP/HTTPS Maven repositories with:
/// - Configurable timeout
/// - Retry with exponential backoff
/// - Connection pooling
/// - Checksum verification
/// - SNAPSHOT resolution
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pool/pool.dart';

import 'artifact_coordinate.dart';
import 'checksum.dart';
import 'local_repository.dart';
import 'maven_metadata.dart';
import 'repository.dart';
import 'repository_exception.dart';
import '../version/maven_version.dart';

/// Configuration for remote repository operations.
final class RemoteRepositoryConfig {
  /// Timeout for individual HTTP requests.
  final Duration timeout;

  /// Maximum number of retry attempts.
  final int maxRetries;

  /// Base delay for exponential backoff (doubles each retry).
  final Duration retryDelay;

  /// Maximum concurrent HTTP requests.
  final int maxConcurrentRequests;

  /// Checksum verification policy.
  final ChecksumPolicy checksumPolicy;

  /// Update policy for SNAPSHOT versions.
  final UpdatePolicy updatePolicy;

  const RemoteRepositoryConfig({
    this.timeout = const Duration(seconds: 30),
    this.maxRetries = 3,
    this.retryDelay = const Duration(seconds: 1),
    this.maxConcurrentRequests = 4,
    this.checksumPolicy = ChecksumPolicy.warn,
    this.updatePolicy = UpdatePolicy.always,
  });
}

/// A remote Maven repository that fetches over HTTP/HTTPS.
final class RemoteRepository implements Repository {
  @override
  final String id;

  /// The base URL of the repository.
  final Uri baseUrl;

  /// Configuration for this repository.
  final RemoteRepositoryConfig config;

  /// Optional local repository for caching.
  final LocalRepository? localCache;

  /// HTTP client for requests.
  final http.Client _client;

  /// Pool for limiting concurrent requests.
  final Pool _pool;

  /// Checksum verifier.
  final ChecksumVerifier _checksumVerifier;

  /// SNAPSHOT resolver.
  final SnapshotResolver _snapshotResolver;

  /// Warning logger function.
  final void Function(String message)? onWarning;

  /// Creates a remote repository.
  RemoteRepository({
    required String url,
    this.id = 'central',
    this.config = const RemoteRepositoryConfig(),
    this.localCache,
    this.onWarning,
    http.Client? client,
  })  : baseUrl = Uri.parse(url.endsWith('/') ? url : '$url/'),
        _client = client ?? http.Client(),
        _pool = Pool(config.maxConcurrentRequests),
        _checksumVerifier = const ChecksumVerifier(),
        _snapshotResolver = const SnapshotResolver();

  @override
  String get location => baseUrl.toString();

  @override
  Future<FetchResult?> fetchPom(ArtifactCoordinate coord) async {
    final path = await _resolveSnapshotPath(coord, 'pom');
    return _fetchWithRetry(
      path,
      coordinate: coord,
      verifyChecksum: true,
    );
  }

  @override
  Future<FetchResult?> fetchArtifact(
    ArtifactCoordinate coord, {
    String? extension,
  }) async {
    final ext = extension ?? coord.packaging;
    final path = await _resolveSnapshotPath(coord, ext);
    return _fetchWithRetry(
      path,
      coordinate: coord,
      verifyChecksum: true,
    );
  }

  @override
  Future<List<MavenVersion>> listVersions(
    String groupId,
    String artifactId,
  ) async {
    final groupPath = groupId.replaceAll('.', '/');
    final metadataPath = '$groupPath/$artifactId/maven-metadata.xml';

    final result = await fetchRaw(metadataPath);
    if (result == null) {
      return [];
    }

    try {
      final metadata = MavenMetadata.parse(result.content, path: metadataPath);
      return metadata.versions;
    } catch (e) {
      _warn('Failed to parse metadata at $metadataPath: $e');
      return [];
    }
  }

  @override
  Future<FetchResult?> fetchRaw(String path) async {
    return _fetchWithRetry(path, verifyChecksum: false);
  }

  /// Resolves the actual path for a SNAPSHOT artifact.
  Future<String> _resolveSnapshotPath(
    ArtifactCoordinate coord,
    String extension,
  ) async {
    if (!coord.isSnapshot) {
      // Not a snapshot, return normal path
      if (extension == 'pom') {
        return coord.pomPath;
      }
      return coord.artifactFilePath(extension);
    }

    // Fetch SNAPSHOT metadata
    final metadataPath = '${coord.artifactPath}/maven-metadata.xml';
    final metadataResult = await fetchRaw(metadataPath);

    if (metadataResult != null) {
      try {
        final metadata = MavenMetadata.parse(
          metadataResult.content,
          path: metadataPath,
        );

        final filename = _snapshotResolver.resolveFilename(
          coord: coord,
          metadata: metadata,
          extension: extension,
        );

        if (filename != null) {
          return '${coord.artifactPath}/$filename';
        }
      } catch (e) {
        _warn('Failed to parse SNAPSHOT metadata: $e');
      }
    }

    // Fallback to literal SNAPSHOT filename
    if (extension == 'pom') {
      return coord.pomPath;
    }
    return coord.artifactFilePath(extension);
  }

  /// Fetches a file with retry logic.
  Future<FetchResult?> _fetchWithRetry(
    String path, {
    ArtifactCoordinate? coordinate,
    bool verifyChecksum = true,
  }) async {
    // Check local cache first
    if (localCache != null) {
      final cached = await localCache!.fetchRaw(path);
      if (cached != null) {
        return cached;
      }
    }

    return _pool.withResource(() async {
      var lastError = Exception('No attempts made');
      var delay = config.retryDelay;

      for (var attempt = 1; attempt <= config.maxRetries; attempt++) {
        try {
          final result = await _fetchOnce(
            path,
            coordinate: coordinate,
            verifyChecksum: verifyChecksum,
          );

          // Cache successful fetch
          if (result != null && localCache != null) {
            await localCache!.save(path, result.content);
          }

          return result;
        } on RepositoryNetworkException catch (e) {
          // 404 means not found, don't retry
          if (e.statusCode == 404) {
            return null;
          }

          lastError = e;
          if (attempt < config.maxRetries) {
            _warn('Attempt $attempt failed for $path, retrying in $delay: $e');
            await Future<void>.delayed(delay);
            delay *= 2; // Exponential backoff
          }
        } on RepositoryTimeoutException catch (e) {
          lastError = e;
          if (attempt < config.maxRetries) {
            _warn('Timeout on attempt $attempt for $path, retrying in $delay');
            await Future<void>.delayed(delay);
            delay *= 2;
          }
        }
      }

      throw RepositoryRetryExhaustedException(
        'Failed to fetch $path after ${config.maxRetries} attempts',
        attempts: config.maxRetries,
        lastError: lastError,
        coordinate: coordinate,
      );
    });
  }

  /// Performs a single fetch attempt.
  Future<FetchResult?> _fetchOnce(
    String path, {
    ArtifactCoordinate? coordinate,
    bool verifyChecksum = true,
  }) async {
    final url = baseUrl.resolve(path);

    try {
      final response = await _client.get(url).timeout(
        config.timeout,
        onTimeout: () {
          throw RepositoryTimeoutException(
            'Request timed out after ${config.timeout}',
            timeout: config.timeout,
            coordinate: coordinate,
          );
        },
      );

      if (response.statusCode == 404) {
        return null;
      }

      if (response.statusCode != 200) {
        throw RepositoryNetworkException(
          'HTTP ${response.statusCode}: ${response.reasonPhrase}',
          url: url.toString(),
          statusCode: response.statusCode,
          coordinate: coordinate,
        );
      }

      var content = Uint8List.fromList(response.bodyBytes);

      // Verify checksum if requested
      if (verifyChecksum && config.checksumPolicy != ChecksumPolicy.ignore) {
        final checksumResult = await _checksumVerifier.verify(
          content: content,
          basePath: path,
          fetchChecksum: (checksumPath) => _fetchRawNoChecksum(checksumPath),
        );

        content = _checksumVerifier.applyPolicy(
          content: content,
          result: checksumResult,
          policy: config.checksumPolicy,
          path: path,
          warn: _warn,
          coordinate: coordinate,
        );
      }

      return FetchResult(content: content, fromCache: false);
    } on RepositoryException {
      rethrow;
    } on TimeoutException catch (e) {
      throw RepositoryTimeoutException(
        'Request timed out',
        timeout: config.timeout,
        coordinate: coordinate,
        cause: e,
      );
    } on SocketException catch (e) {
      throw RepositoryNetworkException(
        'Network error: ${e.message}',
        url: url.toString(),
        coordinate: coordinate,
        cause: e,
      );
    } on http.ClientException catch (e) {
      throw RepositoryNetworkException(
        'HTTP client error: ${e.message}',
        url: url.toString(),
        coordinate: coordinate,
        cause: e,
      );
    }
  }

  /// Fetches raw content without checksum verification (for checksum files).
  Future<FetchResult?> _fetchRawNoChecksum(String path) async {
    final url = baseUrl.resolve(path);

    try {
      final response = await _client.get(url).timeout(config.timeout);

      if (response.statusCode == 404) {
        return null;
      }

      if (response.statusCode != 200) {
        return null; // Treat other errors as missing for checksums
      }

      return FetchResult(
        content: Uint8List.fromList(response.bodyBytes),
        fromCache: false,
      );
    } catch (_) {
      return null; // Treat any error as missing checksum
    }
  }

  void _warn(String message) {
    onWarning?.call(message);
  }

  @override
  Future<void> close() async {
    _client.close();
    await _pool.close();
  }
}

/// Well-known Maven repositories.
abstract final class MavenRepositories {
  /// Maven Central repository.
  static const String central = 'https://repo1.maven.org/maven2/';

  /// Google's Maven repository.
  static const String google = 'https://maven.google.com/';

  /// JCenter repository (deprecated but still used).
  static const String jcenter = 'https://jcenter.bintray.com/';

  /// Creates a remote repository for Maven Central.
  static RemoteRepository createCentral({
    RemoteRepositoryConfig config = const RemoteRepositoryConfig(),
    LocalRepository? localCache,
  }) {
    return RemoteRepository(
      url: central,
      id: 'central',
      config: config,
      localCache: localCache,
    );
  }

  /// Creates a remote repository for Google Maven.
  static RemoteRepository createGoogle({
    RemoteRepositoryConfig config = const RemoteRepositoryConfig(),
    LocalRepository? localCache,
  }) {
    return RemoteRepository(
      url: google,
      id: 'google',
      config: config,
      localCache: localCache,
    );
  }
}
