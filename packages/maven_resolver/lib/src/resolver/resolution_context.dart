/// Resolution result and context for Maven dependency resolution.
///
/// Contains the final result of dependency resolution and the
/// per-resolution state used during resolution.
library;

import '../pom/dependency.dart';
import '../pom/pom.dart';
import '../repository/artifact_coordinate.dart';
import 'dependency_node.dart';

/// The result of resolving dependencies.
///
/// Contains:
/// - The flat list of resolved artifacts
/// - The dependency tree for visualization
/// - Any conflicts that were resolved
/// - Any warnings (non-fatal issues like relocations)
/// - Any errors that occurred
final class ResolutionResult {
  /// The resolved artifacts (flat list, de-duplicated).
  final List<ResolvedArtifact> artifacts;

  /// The dependency tree roots.
  final List<DependencyNode> roots;

  /// Conflicts that were resolved during resolution.
  final List<ResolutionConflict> conflicts;

  /// Warnings encountered during resolution (non-fatal issues).
  final List<ResolutionWarning> warnings;

  /// Errors encountered during resolution.
  final List<ResolutionError> errors;

  /// Creates a resolution result.
  const ResolutionResult({
    required this.artifacts,
    required this.roots,
    this.conflicts = const [],
    this.warnings = const [],
    this.errors = const [],
  });

  /// Creates an empty result.
  static const ResolutionResult empty = ResolutionResult(
    artifacts: [],
    roots: [],
  );

  /// Whether resolution completed without errors.
  bool get isSuccess => errors.isEmpty;

  /// Whether there are any resolved artifacts.
  bool get isEmpty => artifacts.isEmpty;

  /// Whether there are any resolved artifacts.
  bool get isNotEmpty => artifacts.isNotEmpty;

  /// The number of resolved artifacts.
  int get length => artifacts.length;

  /// Returns artifacts filtered by scope.
  List<ResolvedArtifact> forScope(DependencyScope scope) {
    return artifacts.where((a) => a.scope == scope).toList();
  }

  /// Returns artifacts for compile classpath.
  List<ResolvedArtifact> get compileArtifacts {
    return artifacts
        .where(
          (a) =>
              a.scope == DependencyScope.compile ||
              a.scope == DependencyScope.provided ||
              a.scope == DependencyScope.system,
        )
        .toList();
  }

  /// Returns artifacts for runtime classpath.
  List<ResolvedArtifact> get runtimeArtifacts {
    return artifacts
        .where(
          (a) =>
              a.scope == DependencyScope.compile ||
              a.scope == DependencyScope.runtime,
        )
        .toList();
  }

  /// Returns artifacts for test classpath.
  List<ResolvedArtifact> get testArtifacts {
    // Test classpath includes everything
    return artifacts.toList();
  }

  @override
  String toString() {
    final buffer = StringBuffer('ResolutionResult(\n');
    buffer.writeln('  ${artifacts.length} artifacts,');
    buffer.writeln('  ${conflicts.length} conflicts,');
    buffer.writeln('  ${warnings.length} warnings,');
    buffer.writeln('  ${errors.length} errors');
    buffer.writeln(')');
    return buffer.toString();
  }
}

/// An error that occurred during resolution.
final class ResolutionError {
  /// The artifact that caused the error.
  final ArtifactCoordinate? coordinate;

  /// The error message.
  final String message;

  /// The underlying exception, if any.
  final Object? cause;

  /// The stack trace, if any.
  final StackTrace? stackTrace;

  const ResolutionError({
    this.coordinate,
    required this.message,
    this.cause,
    this.stackTrace,
  });

  @override
  String toString() {
    if (coordinate != null) {
      return 'ResolutionError($coordinate): $message';
    }
    return 'ResolutionError: $message';
  }
}

/// A warning that occurred during resolution.
///
/// Warnings are non-fatal issues that don't prevent resolution but
/// should be reported to the user, such as relocations.
final class ResolutionWarning {
  /// The artifact that caused the warning.
  final ArtifactCoordinate? coordinate;

  /// The warning message.
  final String message;

  const ResolutionWarning({
    this.coordinate,
    required this.message,
  });

  @override
  String toString() {
    if (coordinate != null) {
      return 'ResolutionWarning($coordinate): $message';
    }
    return 'ResolutionWarning: $message';
  }
}

/// Per-resolution state.
///
/// This is created fresh for each resolution call and holds all
/// mutable state needed during resolution. This ensures thread-safety
/// and prevents state leakage between resolutions.
final class ResolutionContext {
  /// Resolved artifacts by conflict key (groupId:artifactId).
  final Map<String, ResolvedArtifact> resolved = {};

  /// The depth at which each artifact was first encountered.
  final Map<String, int> depthByKey = {};

  /// The version selected for each artifact key.
  final Map<String, String> versionByKey = {};

  /// Declaration order for tie-breaking.
  final Map<String, int> declarationOrder = {};

  /// Counter for declaration order.
  int _declarationCounter = 0;

  /// Artifacts currently being processed (for cycle detection).
  final Set<String> processing = {};

  /// Cached effective POMs.
  final Map<String, EffectivePom> pomCache = {};

  /// Collected conflicts.
  final List<ResolutionConflict> conflicts = [];

  /// Collected errors.
  final List<ResolutionError> errors = [];

  /// Collected warnings (non-fatal issues like relocations).
  final List<ResolutionWarning> warnings = [];

  /// The effective dependencyManagement entries.
  ///
  /// These are populated from the root POM and any imported BOMs.
  /// Key is conflictKey (groupId:artifactId).
  final Map<String, Dependency> dependencyManagement = {};

  /// Creates a new resolution context.
  ResolutionContext();

  /// Records the declaration order for an artifact.
  void recordDeclaration(String key) {
    if (!declarationOrder.containsKey(key)) {
      declarationOrder[key] = _declarationCounter++;
    }
  }

  /// Checks if an artifact has already been resolved.
  bool isResolved(String key) => resolved.containsKey(key);

  /// Checks if an artifact is currently being processed.
  bool isProcessing(String key) => processing.contains(key);

  /// Gets the resolved artifact for a key.
  ResolvedArtifact? getResolved(String key) => resolved[key];

  /// Registers a resolved artifact.
  void addResolved(ResolvedArtifact artifact) {
    final key = artifact.conflictKey;
    resolved[key] = artifact;
    depthByKey[key] = artifact.depth;
    versionByKey[key] = artifact.coordinate.version;
  }

  /// Checks if a new artifact at the given depth should replace an existing one.
  ///
  /// Returns true if:
  /// - The artifact hasn't been resolved yet, OR
  /// - The new depth is shallower (nearer wins)
  bool shouldResolve(String key, int depth) {
    if (!isResolved(key)) return true;
    final existingDepth = depthByKey[key];
    return existingDepth != null && depth < existingDepth;
  }

  /// Adds an error to the context.
  void addError(ResolutionError error) {
    errors.add(error);
  }

  /// Adds a warning to the context.
  void addWarning(ResolutionWarning warning) {
    warnings.add(warning);
  }

  /// Adds a conflict to the context.
  void addConflict(ResolutionConflict conflict) {
    conflicts.add(conflict);
  }

  /// Caches an effective POM.
  void cachePom(String key, EffectivePom pom) {
    pomCache[key] = pom;
  }

  /// Gets a cached effective POM.
  EffectivePom? getCachedPom(String key) => pomCache[key];

  /// Looks up a managed dependency.
  Dependency? getManagedDependency(String key) => dependencyManagement[key];

  /// Adds managed dependencies from a POM.
  void addManagedDependencies(List<Dependency> deps) {
    for (final dep in deps) {
      // First declaration wins
      dependencyManagement.putIfAbsent(dep.conflictKey, () => dep);
    }
  }
}
