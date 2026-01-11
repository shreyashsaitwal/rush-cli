/// Maven metadata parsing for version listing and SNAPSHOT resolution.
///
/// Parses `maven-metadata.xml` files from Maven repositories.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../version/maven_version.dart';
import 'artifact_coordinate.dart';
import 'repository_exception.dart';

/// Maven metadata from a `maven-metadata.xml` file.
///
/// This metadata is used for:
/// - Listing available versions of an artifact
/// - Resolving SNAPSHOT versions to timestamped builds
final class MavenMetadata {
  /// The group ID.
  final String groupId;

  /// The artifact ID.
  final String artifactId;

  /// The version (only set for SNAPSHOT metadata).
  final String? version;

  /// Versioning information.
  final Versioning? versioning;

  const MavenMetadata({
    required this.groupId,
    required this.artifactId,
    this.version,
    this.versioning,
  });

  /// Parses metadata from XML content.
  factory MavenMetadata.parse(Uint8List content, {String? path}) {
    try {
      final xml = utf8.decode(content);
      final document = XmlDocument.parse(xml);
      final root = document.rootElement;

      if (root.name.local != 'metadata') {
        throw MetadataParseException(
          'Expected <metadata> root element, got <${root.name.local}>',
          metadataPath: path ?? 'unknown',
        );
      }

      final groupId = root.getElement('groupId')?.innerText ?? '';
      final artifactId = root.getElement('artifactId')?.innerText ?? '';
      final version = root.getElement('version')?.innerText;

      final versioningElement = root.getElement('versioning');
      final versioning = versioningElement != null
          ? Versioning._parse(versioningElement)
          : null;

      return MavenMetadata(
        groupId: groupId,
        artifactId: artifactId,
        version: version,
        versioning: versioning,
      );
    } on XmlParserException catch (e) {
      throw MetadataParseException(
        'Failed to parse XML: ${e.message}',
        metadataPath: path ?? 'unknown',
        cause: e,
      );
    }
  }

  /// Returns all available versions, sorted.
  List<MavenVersion> get versions {
    final versionStrings = versioning?.versions ?? [];
    final parsed = versionStrings.map(MavenVersion.parse).toList();
    parsed.sort();
    return parsed;
  }

  /// Returns the latest version, if available.
  MavenVersion? get latest {
    final v = versioning?.latest;
    return v != null ? MavenVersion.parse(v) : null;
  }

  /// Returns the release version, if available.
  MavenVersion? get release {
    final v = versioning?.release;
    return v != null ? MavenVersion.parse(v) : null;
  }
}

/// Versioning information from metadata.
final class Versioning {
  /// The latest version (may include SNAPSHOTs).
  final String? latest;

  /// The latest release version (excludes SNAPSHOTs).
  final String? release;

  /// List of all available versions.
  final List<String> versions;

  /// Snapshot information (only for SNAPSHOT version metadata).
  final Snapshot? snapshot;

  /// Snapshot version entries (only for SNAPSHOT version metadata).
  final List<SnapshotVersion> snapshotVersions;

  /// When this metadata was last updated (yyyyMMddHHmmss format).
  final String? lastUpdated;

  const Versioning({
    this.latest,
    this.release,
    this.versions = const [],
    this.snapshot,
    this.snapshotVersions = const [],
    this.lastUpdated,
  });

  factory Versioning._parse(XmlElement element) {
    final latest = element.getElement('latest')?.innerText;
    final release = element.getElement('release')?.innerText;
    final lastUpdated = element.getElement('lastUpdated')?.innerText;

    final versionsElement = element.getElement('versions');
    final versions = versionsElement
            ?.findElements('version')
            .map((e) => e.innerText)
            .toList() ??
        [];

    final snapshotElement = element.getElement('snapshot');
    final snapshot =
        snapshotElement != null ? Snapshot._parse(snapshotElement) : null;

    final snapshotVersionsElement = element.getElement('snapshotVersions');
    final snapshotVersions = snapshotVersionsElement
            ?.findElements('snapshotVersion')
            .map(SnapshotVersion._parse)
            .toList() ??
        [];

    return Versioning(
      latest: latest,
      release: release,
      versions: versions,
      snapshot: snapshot,
      snapshotVersions: snapshotVersions,
      lastUpdated: lastUpdated,
    );
  }
}

/// Snapshot build information.
final class Snapshot {
  /// The timestamp of the snapshot (yyyyMMdd.HHmmss format).
  final String timestamp;

  /// The build number.
  final int buildNumber;

  /// Whether this is a local snapshot (no timestamp).
  final bool localCopy;

  const Snapshot({
    required this.timestamp,
    required this.buildNumber,
    this.localCopy = false,
  });

  factory Snapshot._parse(XmlElement element) {
    final localCopy = element.getElement('localCopy')?.innerText == 'true';

    if (localCopy) {
      return const Snapshot(timestamp: '', buildNumber: 0, localCopy: true);
    }

    final timestamp = element.getElement('timestamp')?.innerText ?? '';
    final buildNumberStr = element.getElement('buildNumber')?.innerText ?? '0';
    final buildNumber = int.tryParse(buildNumberStr) ?? 0;

    return Snapshot(
      timestamp: timestamp,
      buildNumber: buildNumber,
      localCopy: false,
    );
  }
}

/// A specific snapshot version entry.
final class SnapshotVersion {
  /// The file extension (e.g., 'jar', 'pom').
  final String extension;

  /// The resolved version value (e.g., '1.0-20231128.143052-42').
  final String value;

  /// When this entry was last updated (yyyyMMddHHmmss format).
  final String? updated;

  /// Optional classifier (e.g., 'sources', 'javadoc').
  final String? classifier;

  const SnapshotVersion({
    required this.extension,
    required this.value,
    this.updated,
    this.classifier,
  });

  factory SnapshotVersion._parse(XmlElement element) {
    return SnapshotVersion(
      extension: element.getElement('extension')?.innerText ?? 'jar',
      value: element.getElement('value')?.innerText ?? '',
      updated: element.getElement('updated')?.innerText,
      classifier: element.getElement('classifier')?.innerText,
    );
  }
}

/// Resolves SNAPSHOT versions to their timestamped equivalents.
final class SnapshotResolver {
  const SnapshotResolver();

  /// Resolves a SNAPSHOT version to its timestamped filename.
  ///
  /// If [metadata] is provided, uses the snapshot version entries.
  /// Otherwise, falls back to constructing from timestamp/buildNumber.
  ///
  /// Returns null if resolution fails.
  String? resolveFilename({
    required ArtifactCoordinate coord,
    required MavenMetadata metadata,
    String? extension,
  }) {
    if (!coord.isSnapshot) {
      return null; // Not a snapshot
    }

    final ext = extension ?? 'jar';
    final classifier = coord.classifier;

    // Try to find matching entry in snapshotVersions
    final versioning = metadata.versioning;
    if (versioning != null) {
      for (final sv in versioning.snapshotVersions) {
        if (sv.extension == ext &&
            (classifier == null
                ? sv.classifier == null
                : sv.classifier == classifier)) {
          // Found matching entry
          final resolvedVersion = sv.value;
          return _buildFilename(
            coord.artifactId,
            resolvedVersion,
            classifier,
            ext,
          );
        }
      }

      // Fallback: construct from timestamp/buildNumber
      final snapshot = versioning.snapshot;
      if (snapshot != null &&
          !snapshot.localCopy &&
          snapshot.timestamp.isNotEmpty) {
        final baseVersion = coord.version.replaceFirst('-SNAPSHOT', '');
        final resolvedVersion =
            '$baseVersion-${snapshot.timestamp}-${snapshot.buildNumber}';
        return _buildFilename(
          coord.artifactId,
          resolvedVersion,
          classifier,
          ext,
        );
      }
    }

    return null;
  }

  String _buildFilename(
    String artifactId,
    String version,
    String? classifier,
    String extension,
  ) {
    final buffer = StringBuffer('$artifactId-$version');
    if (classifier != null) {
      buffer.write('-$classifier');
    }
    buffer.write('.$extension');
    return buffer.toString();
  }
}
