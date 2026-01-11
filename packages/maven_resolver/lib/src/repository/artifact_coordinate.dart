/// Represents a Maven artifact coordinate with up to 5 parts.
///
/// Maven coordinates uniquely identify an artifact with:
/// - groupId: The organization/project group (e.g., 'org.apache.maven')
/// - artifactId: The artifact name (e.g., 'maven-core')
/// - version: The version string (e.g., '3.6.0', '1.0-SNAPSHOT')
/// - packaging: The type/extension (default: 'jar')
/// - classifier: Optional classifier (e.g., 'sources', 'javadoc')
///
/// Coordinate string formats:
/// - 3-part: `groupId:artifactId:version`
/// - 4-part: `groupId:artifactId:packaging:version`
/// - 5-part: `groupId:artifactId:packaging:classifier:version`
library;

import '../version/maven_version.dart';

/// A Maven artifact coordinate.
///
/// Use [ArtifactCoordinate.parse] to create from a string, or the constructor
/// for programmatic creation.
final class ArtifactCoordinate {
  /// The organization/project group identifier.
  final String groupId;

  /// The artifact name.
  final String artifactId;

  /// The version string.
  final String version;

  /// The packaging type (default: 'jar').
  final String packaging;

  /// Optional classifier (e.g., 'sources', 'javadoc').
  final String? classifier;

  /// Creates a new artifact coordinate.
  const ArtifactCoordinate({
    required this.groupId,
    required this.artifactId,
    required this.version,
    this.packaging = 'jar',
    this.classifier,
  });

  /// Parses a coordinate string into an [ArtifactCoordinate].
  ///
  /// Supported formats:
  /// - `groupId:artifactId:version` (3-part)
  /// - `groupId:artifactId:packaging:version` (4-part)
  /// - `groupId:artifactId:packaging:classifier:version` (5-part)
  ///
  /// Throws [FormatException] if the string is not a valid coordinate.
  factory ArtifactCoordinate.parse(String coord) {
    final parts = coord.split(':');

    switch (parts.length) {
      case 3:
        // groupId:artifactId:version
        return ArtifactCoordinate(
          groupId: parts[0],
          artifactId: parts[1],
          version: parts[2],
        );
      case 4:
        // groupId:artifactId:packaging:version
        return ArtifactCoordinate(
          groupId: parts[0],
          artifactId: parts[1],
          packaging: parts[2],
          version: parts[3],
        );
      case 5:
        // groupId:artifactId:packaging:classifier:version
        return ArtifactCoordinate(
          groupId: parts[0],
          artifactId: parts[1],
          packaging: parts[2],
          classifier: parts[3].isEmpty ? null : parts[3],
          version: parts[4],
        );
      default:
        throw FormatException('Invalid artifact coordinate: "$coord"');
    }
  }

  /// Returns the groupId as a path (dots replaced with slashes).
  ///
  /// Example: `org.apache.maven` → `org/apache/maven`
  String get groupPath => groupId.replaceAll('.', '/');

  /// Returns the base filename for this artifact (without extension).
  ///
  /// Format: `artifactId-version[-classifier]`
  String get baseFilename {
    final buffer = StringBuffer('$artifactId-$version');
    if (classifier != null) {
      buffer.write('-$classifier');
    }
    return buffer.toString();
  }

  /// Returns the filename for the POM file.
  String get pomFilename => '$artifactId-$version.pom';

  /// Returns the filename for the artifact with the given extension.
  String artifactFilename([String? extension]) {
    final ext = extension ?? _packagingToExtension(packaging);
    return '$baseFilename.$ext';
  }

  /// Returns the repository path to the artifact directory.
  ///
  /// Format: `groupPath/artifactId/version`
  String get artifactPath => '$groupPath/$artifactId/$version';

  /// Returns the full path to the POM file in the repository.
  String get pomPath => '$artifactPath/$pomFilename';

  /// Returns the full path to the artifact file in the repository.
  String artifactFilePath([String? extension]) {
    return '$artifactPath/${artifactFilename(extension)}';
  }

  /// Whether this is a SNAPSHOT version.
  bool get isSnapshot => version.endsWith('-SNAPSHOT');

  /// Returns the parsed version.
  MavenVersion get parsedVersion => MavenVersion.parse(version);

  /// Returns a copy with the specified fields replaced.
  ArtifactCoordinate copyWith({
    String? groupId,
    String? artifactId,
    String? version,
    String? packaging,
    String? classifier,
  }) {
    return ArtifactCoordinate(
      groupId: groupId ?? this.groupId,
      artifactId: artifactId ?? this.artifactId,
      version: version ?? this.version,
      packaging: packaging ?? this.packaging,
      classifier: classifier ?? this.classifier,
    );
  }

  /// Returns the canonical coordinate string.
  ///
  /// Format depends on whether classifier is present:
  /// - With classifier: `groupId:artifactId:packaging:classifier:version`
  /// - Without classifier: `groupId:artifactId:packaging:version`
  @override
  String toString() {
    if (classifier != null) {
      return '$groupId:$artifactId:$packaging:$classifier:$version';
    }
    if (packaging != 'jar') {
      return '$groupId:$artifactId:$packaging:$version';
    }
    return '$groupId:$artifactId:$version';
  }

  /// Returns a unique key for this artifact (groupId:artifactId:classifier).
  ///
  /// This is used for conflict resolution where different versions of the
  /// same artifact need to be compared.
  String get conflictKey {
    if (classifier != null) {
      return '$groupId:$artifactId:$classifier';
    }
    return '$groupId:$artifactId';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArtifactCoordinate &&
          groupId == other.groupId &&
          artifactId == other.artifactId &&
          version == other.version &&
          packaging == other.packaging &&
          classifier == other.classifier;

  @override
  int get hashCode => Object.hash(
        groupId,
        artifactId,
        version,
        packaging,
        classifier,
      );

  /// Maps packaging types to file extensions.
  static String _packagingToExtension(String packaging) {
    return switch (packaging) {
      'bundle' => 'jar',
      'eclipse-plugin' => 'jar',
      'maven-plugin' => 'jar',
      'ejb' => 'jar',
      'ejb-client' => 'jar',
      'test-jar' => 'jar',
      'java-source' => 'jar',
      'javadoc' => 'jar',
      _ => packaging,
    };
  }
}
