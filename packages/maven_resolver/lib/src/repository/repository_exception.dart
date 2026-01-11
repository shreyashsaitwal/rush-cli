/// Repository exceptions for Maven artifact resolution.
library;

import 'artifact_coordinate.dart';

/// Base class for all repository-related exceptions.
sealed class RepositoryException implements Exception {
  /// A human-readable description of the error.
  final String message;

  /// The coordinate that caused the error, if applicable.
  final ArtifactCoordinate? coordinate;

  /// The underlying cause, if any.
  final Object? cause;

  const RepositoryException(this.message, {this.coordinate, this.cause});

  @override
  String toString() {
    final buffer = StringBuffer(runtimeType.toString());
    buffer.write(': $message');
    if (coordinate != null) {
      buffer.write(' ($coordinate)');
    }
    if (cause != null) {
      buffer.write('\nCaused by: $cause');
    }
    return buffer.toString();
  }
}

/// Thrown when an artifact cannot be found in any repository.
final class ArtifactNotFoundException extends RepositoryException {
  /// The repositories that were searched.
  final List<String> searchedRepositories;

  const ArtifactNotFoundException(
    super.message, {
    super.coordinate,
    this.searchedRepositories = const [],
  });
}

/// Thrown when a network operation fails.
final class RepositoryNetworkException extends RepositoryException {
  /// The URL that failed.
  final String url;

  /// The HTTP status code, if available.
  final int? statusCode;

  const RepositoryNetworkException(
    super.message, {
    required this.url,
    this.statusCode,
    super.coordinate,
    super.cause,
  });
}

/// Thrown when checksum verification fails.
final class ChecksumVerificationException extends RepositoryException {
  /// The expected checksum.
  final String expected;

  /// The actual checksum.
  final String actual;

  /// The checksum algorithm (e.g., 'sha1', 'md5').
  final String algorithm;

  const ChecksumVerificationException(
    super.message, {
    required this.expected,
    required this.actual,
    required this.algorithm,
    super.coordinate,
  });
}

/// Thrown when a checksum file is missing and the policy requires it.
final class ChecksumMissingException extends RepositoryException {
  /// The path to the missing checksum file.
  final String checksumPath;

  const ChecksumMissingException(
    super.message, {
    required this.checksumPath,
    super.coordinate,
  });
}

/// Thrown when an operation times out.
final class RepositoryTimeoutException extends RepositoryException {
  /// The timeout duration.
  final Duration timeout;

  const RepositoryTimeoutException(
    super.message, {
    required this.timeout,
    super.coordinate,
    super.cause,
  });
}

/// Thrown when retries are exhausted.
final class RepositoryRetryExhaustedException extends RepositoryException {
  /// The number of attempts made.
  final int attempts;

  /// The last error that occurred.
  final Object lastError;

  const RepositoryRetryExhaustedException(
    super.message, {
    required this.attempts,
    required this.lastError,
    super.coordinate,
  });
}

/// Thrown when metadata is malformed or cannot be parsed.
final class MetadataParseException extends RepositoryException {
  /// The path to the metadata file.
  final String metadataPath;

  const MetadataParseException(
    super.message, {
    required this.metadataPath,
    super.coordinate,
    super.cause,
  });
}
