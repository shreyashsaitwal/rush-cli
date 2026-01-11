/// Exclusion model for Maven dependencies.
///
/// Exclusions prevent specific transitive dependencies from being included.
library;

/// A dependency exclusion pattern.
///
/// Exclusions are applied to the entire subtree below a dependency.
/// They match on groupId and artifactId only (no version).
///
/// Example:
/// ```xml
/// <exclusion>
///   <groupId>org.slf4j</groupId>
///   <artifactId>slf4j-log4j12</artifactId>
/// </exclusion>
/// ```
final class Exclusion {
  /// The group ID to exclude. Use `*` to match any group.
  final String groupId;

  /// The artifact ID to exclude. Use `*` to match any artifact.
  final String artifactId;

  /// Creates an exclusion for the given group and artifact.
  const Exclusion({
    required this.groupId,
    required this.artifactId,
  });

  /// A wildcard exclusion that matches all dependencies.
  static const Exclusion all = Exclusion(groupId: '*', artifactId: '*');

  /// Whether this is a wildcard exclusion (matches all).
  bool get isWildcard => groupId == '*' && artifactId == '*';

  /// Checks if this exclusion matches the given coordinates.
  ///
  /// Supports wildcards for groupId and/or artifactId.
  bool matches(String otherGroupId, String otherArtifactId) {
    final groupMatches = groupId == '*' || groupId == otherGroupId;
    final artifactMatches = artifactId == '*' || artifactId == otherArtifactId;
    return groupMatches && artifactMatches;
  }

  /// Returns the key for this exclusion (groupId:artifactId).
  String get key => '$groupId:$artifactId';

  @override
  String toString() => key;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Exclusion &&
          groupId == other.groupId &&
          artifactId == other.artifactId;

  @override
  int get hashCode => Object.hash(groupId, artifactId);
}

/// A set of exclusions that can be efficiently checked.
final class ExclusionSet {
  final Set<Exclusion> _exclusions;
  final bool _hasWildcard;

  /// Creates an exclusion set from the given list.
  ExclusionSet(Iterable<Exclusion> exclusions)
      : _exclusions = Set.of(exclusions),
        _hasWildcard = exclusions.any((e) => e.isWildcard);

  /// An empty exclusion set.
  static const ExclusionSet empty = ExclusionSet._empty();

  const ExclusionSet._empty()
      : _exclusions = const {},
        _hasWildcard = false;

  /// Whether this set has any exclusions.
  bool get isEmpty => _exclusions.isEmpty;

  /// Whether this set has any exclusions.
  bool get isNotEmpty => _exclusions.isNotEmpty;

  /// The number of exclusions in this set.
  int get length => _exclusions.length;

  /// Checks if any exclusion in this set matches the given coordinates.
  bool matches(String groupId, String artifactId) {
    if (_hasWildcard) return true;
    return _exclusions.any((e) => e.matches(groupId, artifactId));
  }

  /// Returns a new set with the given exclusions added.
  ExclusionSet merge(Iterable<Exclusion> other) {
    if (other.isEmpty) return this;
    return ExclusionSet({..._exclusions, ...other});
  }

  /// The exclusions in this set.
  Iterable<Exclusion> get exclusions => _exclusions;

  @override
  String toString() => _exclusions.toString();
}
