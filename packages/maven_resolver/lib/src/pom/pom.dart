/// Immutable POM model.
///
/// Represents a parsed Maven POM file with all its elements.
/// This is a raw representation before property interpolation.
library;

import 'dependency.dart';
import '../repository/artifact_coordinate.dart';

/// A parent POM reference.
final class ParentRef {
  /// The parent's group ID.
  final String groupId;

  /// The parent's artifact ID.
  final String artifactId;

  /// The parent's version.
  final String version;

  /// Relative path to the parent POM (default: ../pom.xml).
  final String relativePath;

  const ParentRef({
    required this.groupId,
    required this.artifactId,
    required this.version,
    this.relativePath = '../pom.xml',
  });

  /// Returns the coordinate for fetching this parent.
  ArtifactCoordinate get coordinate => ArtifactCoordinate(
        groupId: groupId,
        artifactId: artifactId,
        version: version,
        packaging: 'pom',
      );

  @override
  String toString() => '$groupId:$artifactId:$version';
}

/// License information from a POM.
final class License {
  final String? name;
  final String? url;
  final String? distribution;
  final String? comments;

  const License({
    this.name,
    this.url,
    this.distribution,
    this.comments,
  });
}

/// SCM (Source Control Management) information.
final class Scm {
  final String? connection;
  final String? developerConnection;
  final String? url;
  final String? tag;

  const Scm({
    this.connection,
    this.developerConnection,
    this.url,
    this.tag,
  });
}

/// Distribution management information.
final class DistributionManagement {
  final Relocation? relocation;

  const DistributionManagement({this.relocation});
}

/// Relocation information for moved artifacts.
final class Relocation {
  final String? groupId;
  final String? artifactId;
  final String? version;
  final String? message;

  const Relocation({
    this.groupId,
    this.artifactId,
    this.version,
    this.message,
  });

  /// Whether this relocation changes anything.
  bool get isEffective =>
      groupId != null || artifactId != null || version != null;
}

/// An immutable Maven POM representation.
///
/// This represents the raw POM as parsed from XML, before any
/// property interpolation or parent merging has occurred.
final class Pom {
  /// The model version (typically "4.0.0").
  final String? modelVersion;

  /// The group ID (may be inherited from parent).
  final String? groupId;

  /// The artifact ID.
  final String artifactId;

  /// The version (may be inherited from parent).
  final String? version;

  /// The packaging type (default: jar).
  final String packaging;

  /// The project name.
  final String? name;

  /// The project description.
  final String? description;

  /// The project URL.
  final String? url;

  /// Parent POM reference.
  final ParentRef? parent;

  /// Project properties.
  final Map<String, String> properties;

  /// Direct dependencies.
  final List<Dependency> dependencies;

  /// Managed dependencies (version/config templates).
  final List<Dependency> dependencyManagement;

  /// Module paths for multi-module projects.
  final List<String> modules;

  /// Project licenses.
  final List<License> licenses;

  /// Source control information.
  final Scm? scm;

  /// Distribution management.
  final DistributionManagement? distributionManagement;

  /// Creates a POM with the given attributes.
  const Pom({
    this.modelVersion,
    this.groupId,
    required this.artifactId,
    this.version,
    this.packaging = 'jar',
    this.name,
    this.description,
    this.url,
    this.parent,
    this.properties = const {},
    this.dependencies = const [],
    this.dependencyManagement = const [],
    this.modules = const [],
    this.licenses = const [],
    this.scm,
    this.distributionManagement,
  });

  /// Returns the effective group ID (from this POM or parent).
  String get effectiveGroupId => groupId ?? parent?.groupId ?? '';

  /// Returns the effective version (from this POM or parent).
  String get effectiveVersion => version ?? parent?.version ?? '';

  /// Returns the coordinate for this POM.
  ArtifactCoordinate get coordinate => ArtifactCoordinate(
        groupId: effectiveGroupId,
        artifactId: artifactId,
        version: effectiveVersion,
        packaging: packaging,
      );

  /// Whether this POM has a parent.
  bool get hasParent => parent != null;

  /// Whether this POM has any dependencies.
  bool get hasDependencies => dependencies.isNotEmpty;

  /// Whether this POM has any dependencyManagement entries.
  bool get hasDependencyManagement => dependencyManagement.isNotEmpty;

  /// Returns the BOM imports from dependencyManagement.
  List<Dependency> get bomImports =>
      dependencyManagement.where((d) => d.isBomImport).toList();

  /// Returns a copy with the given fields replaced.
  Pom copyWith({
    String? modelVersion,
    String? groupId,
    String? artifactId,
    String? version,
    String? packaging,
    String? name,
    String? description,
    String? url,
    ParentRef? parent,
    Map<String, String>? properties,
    List<Dependency>? dependencies,
    List<Dependency>? dependencyManagement,
    List<String>? modules,
    List<License>? licenses,
    Scm? scm,
    DistributionManagement? distributionManagement,
  }) {
    return Pom(
      modelVersion: modelVersion ?? this.modelVersion,
      groupId: groupId ?? this.groupId,
      artifactId: artifactId ?? this.artifactId,
      version: version ?? this.version,
      packaging: packaging ?? this.packaging,
      name: name ?? this.name,
      description: description ?? this.description,
      url: url ?? this.url,
      parent: parent ?? this.parent,
      properties: properties ?? this.properties,
      dependencies: dependencies ?? this.dependencies,
      dependencyManagement: dependencyManagement ?? this.dependencyManagement,
      modules: modules ?? this.modules,
      licenses: licenses ?? this.licenses,
      scm: scm ?? this.scm,
      distributionManagement:
          distributionManagement ?? this.distributionManagement,
    );
  }

  @override
  String toString() => '$effectiveGroupId:$artifactId:$effectiveVersion';
}

/// The result of merging a POM with its parent chain.
///
/// Contains the effective POM after all inheritance is applied.
final class EffectivePom {
  /// The merged POM.
  final Pom pom;

  /// The parent chain (nearest first).
  final List<Pom> parentChain;

  /// Merged properties from entire chain.
  final Map<String, String> properties;

  /// Merged dependencyManagement from entire chain.
  final List<Dependency> dependencyManagement;

  const EffectivePom({
    required this.pom,
    this.parentChain = const [],
    this.properties = const {},
    this.dependencyManagement = const [],
  });

  /// The group ID.
  String get groupId => pom.effectiveGroupId;

  /// The artifact ID.
  String get artifactId => pom.artifactId;

  /// The version.
  String get version => pom.effectiveVersion;

  /// The packaging.
  String get packaging => pom.packaging;

  /// The direct dependencies.
  List<Dependency> get dependencies => pom.dependencies;

  /// Returns the coordinate.
  ArtifactCoordinate get coordinate => pom.coordinate;

  @override
  String toString() => pom.toString();
}
