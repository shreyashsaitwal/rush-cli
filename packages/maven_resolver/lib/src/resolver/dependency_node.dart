/// Dependency node for the resolution tree.
///
/// Represents a resolved dependency with its position in the tree.
library;

import '../pom/dependency.dart';
import '../pom/exclusion.dart';
import '../repository/artifact_coordinate.dart';

/// A node in the dependency resolution tree.
///
/// Each node represents a resolved artifact with information about:
/// - The artifact coordinate and scope
/// - Its depth in the tree (for "nearest wins" conflict resolution)
/// - Its path from the root (for debugging and exclusion propagation)
/// - Its children (transitive dependencies)
final class DependencyNode {
  /// The resolved artifact coordinate.
  final ArtifactCoordinate coordinate;

  /// The effective scope after mediation.
  final DependencyScope scope;

  /// Whether this dependency was declared optional.
  final bool optional;

  /// The depth in the dependency tree (root dependencies are depth 1).
  final int depth;

  /// The path from the root to this node (list of artifact keys).
  final List<String> path;

  /// The exclusions that apply to this node's transitive dependencies.
  final ExclusionSet exclusions;

  /// Child nodes (transitive dependencies).
  final List<DependencyNode> children;

  /// Whether this node was selected or replaced by a nearer version.
  final bool selected;

  /// If not selected, the key of the node that replaced this one.
  final String? replacedBy;

  /// Creates a dependency node.
  DependencyNode({
    required this.coordinate,
    required this.scope,
    this.optional = false,
    required this.depth,
    required this.path,
    ExclusionSet? exclusions,
    this.children = const [],
    this.selected = true,
    this.replacedBy,
  }) : exclusions = exclusions ?? ExclusionSet.empty;

  /// The unique key for conflict detection (groupId:artifactId).
  String get conflictKey => '${coordinate.groupId}:${coordinate.artifactId}';

  /// The coordinate string including version.
  String get fullCoordinate => coordinate.toString();

  /// Returns a copy with the given fields replaced.
  DependencyNode copyWith({
    ArtifactCoordinate? coordinate,
    DependencyScope? scope,
    bool? optional,
    int? depth,
    List<String>? path,
    ExclusionSet? exclusions,
    List<DependencyNode>? children,
    bool? selected,
    String? replacedBy,
  }) {
    return DependencyNode(
      coordinate: coordinate ?? this.coordinate,
      scope: scope ?? this.scope,
      optional: optional ?? this.optional,
      depth: depth ?? this.depth,
      path: path ?? this.path,
      exclusions: exclusions ?? this.exclusions,
      children: children ?? this.children,
      selected: selected ?? this.selected,
      replacedBy: replacedBy ?? this.replacedBy,
    );
  }

  /// Returns a copy with [selected] set to false and [replacedBy] set.
  DependencyNode markReplaced(String byKey) {
    return copyWith(selected: false, replacedBy: byKey);
  }

  /// Returns a copy with the given children.
  DependencyNode withChildren(List<DependencyNode> newChildren) {
    return copyWith(children: newChildren);
  }

  @override
  String toString() {
    final scopeStr = scope != DependencyScope.compile ? ' ($scope)' : '';
    final depthStr = 'depth=$depth';
    return '$fullCoordinate$scopeStr [$depthStr]';
  }
}

/// A resolved artifact ready for download/use.
///
/// This represents the final resolution result for a single artifact,
/// containing all information needed to fetch and use the artifact.
final class ResolvedArtifact {
  /// The artifact coordinate.
  final ArtifactCoordinate coordinate;

  /// The effective scope.
  final DependencyScope scope;

  /// Whether this was an optional dependency.
  final bool optional;

  /// The depth at which this artifact was first encountered.
  final int depth;

  /// The resolution path (for debugging).
  final List<String> path;

  /// Creates a resolved artifact.
  const ResolvedArtifact({
    required this.coordinate,
    required this.scope,
    this.optional = false,
    required this.depth,
    required this.path,
  });

  /// Creates a resolved artifact from a dependency node.
  factory ResolvedArtifact.fromNode(DependencyNode node) {
    return ResolvedArtifact(
      coordinate: node.coordinate,
      scope: node.scope,
      optional: node.optional,
      depth: node.depth,
      path: node.path,
    );
  }

  /// The unique key for conflict detection.
  String get conflictKey => '${coordinate.groupId}:${coordinate.artifactId}';

  @override
  String toString() => coordinate.toString();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResolvedArtifact && coordinate == other.coordinate;

  @override
  int get hashCode => coordinate.hashCode;
}

/// A conflict between two versions of the same artifact.
final class ResolutionConflict {
  /// The artifact key (groupId:artifactId).
  final String artifactKey;

  /// The selected version.
  final String selectedVersion;

  /// The conflicting version(s) that were not selected.
  final List<String> conflictingVersions;

  /// The depths at which each version was encountered.
  final Map<String, int> depthByVersion;

  /// The reason for the selection.
  final ConflictResolutionReason reason;

  const ResolutionConflict({
    required this.artifactKey,
    required this.selectedVersion,
    required this.conflictingVersions,
    required this.depthByVersion,
    required this.reason,
  });

  @override
  String toString() {
    return '$artifactKey: selected $selectedVersion over '
        '${conflictingVersions.join(", ")} ($reason)';
  }
}

/// The reason a particular version was selected in a conflict.
enum ConflictResolutionReason {
  /// The selected version was closer to the root.
  nearestWins,

  /// Same depth, but selected version was declared first.
  firstDeclaration,

  /// Selected version was mandated by dependencyManagement.
  dependencyManagement,

  /// Only one version was available.
  noConflict,

  /// Selected version satisfied all version range constraints.
  rangeIntersection,
}
