/// Checksum verification for Maven artifacts.
///
/// Supports SHA-1, SHA-256, SHA-512, and MD5 checksums.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import 'repository.dart';
import 'repository_exception.dart';
import 'artifact_coordinate.dart';

/// Supported checksum algorithms in order of preference.
enum ChecksumAlgorithm {
  /// SHA-512 (most secure, but less common).
  sha512('sha512'),

  /// SHA-256 (secure and increasingly common).
  sha256('sha256'),

  /// SHA-1 (most common for Maven).
  sha1('sha1'),

  /// MD5 (legacy, least secure).
  md5('md5');

  /// The file extension for this checksum type.
  final String extension;

  const ChecksumAlgorithm(this.extension);

  /// Computes the checksum of the given data.
  String compute(Uint8List data) {
    final digest = switch (this) {
      ChecksumAlgorithm.sha512 => crypto.sha512.convert(data),
      ChecksumAlgorithm.sha256 => crypto.sha256.convert(data),
      ChecksumAlgorithm.sha1 => crypto.sha1.convert(data),
      ChecksumAlgorithm.md5 => crypto.md5.convert(data),
    };
    return digest.toString();
  }
}

/// Result of checksum verification.
sealed class ChecksumResult {
  const ChecksumResult();
}

/// Checksum verified successfully.
final class ChecksumValid extends ChecksumResult {
  /// The algorithm used.
  final ChecksumAlgorithm algorithm;

  /// The checksum value.
  final String checksum;

  const ChecksumValid(this.algorithm, this.checksum);
}

/// Checksum verification failed.
final class ChecksumInvalid extends ChecksumResult {
  /// The algorithm used.
  final ChecksumAlgorithm algorithm;

  /// The expected checksum from the file.
  final String expected;

  /// The actual computed checksum.
  final String actual;

  const ChecksumInvalid(this.algorithm, this.expected, this.actual);
}

/// No checksum file was found.
final class ChecksumMissing extends ChecksumResult {
  /// The algorithms that were tried.
  final List<ChecksumAlgorithm> triedAlgorithms;

  const ChecksumMissing(this.triedAlgorithms);
}

/// Utility for fetching and verifying checksums.
final class ChecksumVerifier {
  /// The algorithms to try, in order of preference.
  final List<ChecksumAlgorithm> algorithms;

  /// Creates a verifier with the default algorithm order.
  const ChecksumVerifier({
    this.algorithms = const [
      ChecksumAlgorithm.sha1,
      ChecksumAlgorithm.sha256,
      ChecksumAlgorithm.sha512,
      ChecksumAlgorithm.md5,
    ],
  });

  /// Verifies the checksum of the given content.
  ///
  /// Tries each algorithm in order until a checksum file is found.
  /// Returns [ChecksumMissing] if no checksum file exists for any algorithm.
  Future<ChecksumResult> verify({
    required Uint8List content,
    required String basePath,
    required Future<FetchResult?> Function(String path) fetchChecksum,
  }) async {
    for (final algorithm in algorithms) {
      final checksumPath = '$basePath.${algorithm.extension}';
      final result = await fetchChecksum(checksumPath);

      if (result != null) {
        final expectedRaw = utf8.decode(result.content).trim();
        // Checksum files may contain just the hash, or hash + filename
        // Extract just the hash (first word)
        final expected = expectedRaw.split(RegExp(r'\s+')).first.toLowerCase();
        final actual = algorithm.compute(content).toLowerCase();

        if (expected == actual) {
          return ChecksumValid(algorithm, actual);
        } else {
          return ChecksumInvalid(algorithm, expected, actual);
        }
      }
    }

    return ChecksumMissing(algorithms);
  }

  /// Computes the checksum using the preferred algorithm.
  String computePreferred(Uint8List content) {
    return algorithms.first.compute(content);
  }

  /// Applies the checksum policy to a verification result.
  ///
  /// Returns the content if verification passes or policy allows.
  /// Throws [ChecksumVerificationException] or [ChecksumMissingException]
  /// if the policy requires failure.
  Uint8List applyPolicy({
    required Uint8List content,
    required ChecksumResult result,
    required ChecksumPolicy policy,
    required String path,
    required void Function(String message) warn,
    ArtifactCoordinate? coordinate,
  }) {
    switch (result) {
      case ChecksumValid():
        return content;

      case ChecksumInvalid(:final algorithm, :final expected, :final actual):
        switch (policy) {
          case ChecksumPolicy.fail:
            throw ChecksumVerificationException(
              'Checksum verification failed for $path',
              expected: expected,
              actual: actual,
              algorithm: algorithm.extension,
              coordinate: coordinate,
            );
          case ChecksumPolicy.warn:
            warn('Checksum verification failed for $path: '
                'expected $expected, got $actual');
            return content;
          case ChecksumPolicy.ignore:
            return content;
        }

      case ChecksumMissing():
        switch (policy) {
          case ChecksumPolicy.fail:
            throw ChecksumMissingException(
              'No checksum file found for $path',
              checksumPath: path,
              coordinate: coordinate,
            );
          case ChecksumPolicy.warn:
            warn('No checksum file found for $path');
            return content;
          case ChecksumPolicy.ignore:
            return content;
        }
    }
  }
}
