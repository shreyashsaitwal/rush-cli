/// Dependency model for Maven POMs.
///
/// Represents a dependency declaration with all Maven attributes.
library;

import 'exclusion.dart';

/// Maven dependency scope.
///
/// Determines how a dependency is used during different build phases.
enum DependencyScope {
  /// Default scope. Available at compile, runtime, and test time.
  compile,

  /// Like compile, but provided by the JDK or container at runtime.
  provided,

  /// Not needed for compilation, but needed at runtime.
  runtime,

  /// Only available during test compilation and execution.
  test,

  /// Similar to provided, but you specify the JAR path explicitly.
  system,

  /// Used in dependencyManagement to import a BOM's dependencies.
  import_;

  /// Parses a scope string. Returns [compile] for null or unrecognized values.
  static DependencyScope parse(String? value) {
    if (value == null || value.isEmpty) return compile;
    return switch (value.toLowerCase()) {
      'compile' => compile,
      'provided' => provided,
      'runtime' => runtime,
      'test' => test,
      'system' => system,
      'import' => import_,
      _ => compile, // Default to compile for unknown scopes
    };
  }

  /// Returns the string representation for XML output.
  String toXmlString() => switch (this) {
        import_ => 'import',
        _ => name,
      };

  /// Whether this scope is transitive.
  bool get isTransitive => switch (this) {
        compile => true,
        runtime => true,
        _ => false,
      };
}

/// Scope mediation table for transitive dependencies.
///
/// Given a direct scope and transitive scope, returns the effective scope
/// or null if the dependency should be omitted.
DependencyScope? mediateScope(
  DependencyScope direct,
  DependencyScope transitive,
) {
  // Non-transitive scopes are always omitted
  if (!transitive.isTransitive) return null;

  return switch ((direct, transitive)) {
    // compile + compile/runtime → compile/runtime
    (DependencyScope.compile, DependencyScope.compile) =>
      DependencyScope.compile,
    (DependencyScope.compile, DependencyScope.runtime) =>
      DependencyScope.runtime,

    // provided + compile/runtime → provided
    (DependencyScope.provided, DependencyScope.compile) =>
      DependencyScope.provided,
    (DependencyScope.provided, DependencyScope.runtime) =>
      DependencyScope.provided,

    // runtime + compile/runtime → runtime
    (DependencyScope.runtime, DependencyScope.compile) =>
      DependencyScope.runtime,
    (DependencyScope.runtime, DependencyScope.runtime) =>
      DependencyScope.runtime,

    // test + compile/runtime → test
    (DependencyScope.test, DependencyScope.compile) => DependencyScope.test,
    (DependencyScope.test, DependencyScope.runtime) => DependencyScope.test,

    // system + compile/runtime → system
    (DependencyScope.system, DependencyScope.compile) => DependencyScope.system,
    (DependencyScope.system, DependencyScope.runtime) => DependencyScope.system,

    // Everything else is omitted
    _ => null,
  };
}

/// A Maven dependency declaration.
///
/// This represents the raw dependency as declared in a POM file,
/// before interpolation or resolution.
final class Dependency {
  /// The group ID.
  final String groupId;

  /// The artifact ID.
  final String artifactId;

  /// The version (may contain property placeholders).
  final String? version;

  /// The packaging type (default: jar).
  final String type;

  /// Optional classifier (e.g., 'sources', 'javadoc').
  final String? classifier;

  /// The dependency scope.
  final DependencyScope scope;

  /// Whether the scope was explicitly set in the POM.
  ///
  /// When false, the scope should be inherited from dependencyManagement
  /// if available. This is important for correct Maven behavior where
  /// dependencyManagement can provide default scopes.
  final bool scopeExplicit;

  /// Path for system-scoped dependencies.
  final String? systemPath;

  /// Whether this dependency is optional.
  final bool optional;

  /// Exclusions to apply to this dependency's transitives.
  final List<Exclusion> exclusions;

  /// Creates a dependency with the given attributes.
  const Dependency({
    required this.groupId,
    required this.artifactId,
    this.version,
    this.type = 'jar',
    this.classifier,
    this.scope = DependencyScope.compile,
    this.scopeExplicit = true,
    this.systemPath,
    this.optional = false,
    this.exclusions = const [],
  });

  /// Returns a unique key for conflict detection (groupId:artifactId:classifier).
  String get conflictKey {
    if (classifier != null) {
      return '$groupId:$artifactId:$classifier';
    }
    return '$groupId:$artifactId';
  }

  /// Returns the coordinate string.
  String get coordinate {
    final buffer = StringBuffer('$groupId:$artifactId');
    if (type != 'jar') {
      buffer.write(':$type');
    }
    if (classifier != null) {
      if (type == 'jar') buffer.write(':jar');
      buffer.write(':$classifier');
    }
    if (version != null) {
      buffer.write(':$version');
    }
    return buffer.toString();
  }

  /// Whether this is a BOM import (type=pom, scope=import).
  bool get isBomImport => type == 'pom' && scope == DependencyScope.import_;

  /// Returns a copy with the given fields replaced.
  Dependency copyWith({
    String? groupId,
    String? artifactId,
    String? version,
    String? type,
    String? classifier,
    DependencyScope? scope,
    bool? scopeExplicit,
    String? systemPath,
    bool? optional,
    List<Exclusion>? exclusions,
  }) {
    return Dependency(
      groupId: groupId ?? this.groupId,
      artifactId: artifactId ?? this.artifactId,
      version: version ?? this.version,
      type: type ?? this.type,
      classifier: classifier ?? this.classifier,
      scope: scope ?? this.scope,
      scopeExplicit: scopeExplicit ?? this.scopeExplicit,
      systemPath: systemPath ?? this.systemPath,
      optional: optional ?? this.optional,
      exclusions: exclusions ?? this.exclusions,
    );
  }

  @override
  String toString() => coordinate;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Dependency &&
          groupId == other.groupId &&
          artifactId == other.artifactId &&
          version == other.version &&
          type == other.type &&
          classifier == other.classifier &&
          scope == other.scope;

  @override
  int get hashCode => Object.hash(
        groupId,
        artifactId,
        version,
        type,
        classifier,
        scope,
      );
}

/// A managed dependency from dependencyManagement.
///
/// This extends [Dependency] with additional context about
/// where the management entry came from.
final class ManagedDependency {
  /// The dependency configuration.
  final Dependency dependency;

  /// Where this management entry came from.
  final ManagementSource source;

  const ManagedDependency({
    required this.dependency,
    required this.source,
  });
}

/// Source of a dependencyManagement entry.
enum ManagementSource {
  /// Declared directly in the current POM.
  direct,

  /// Inherited from a parent POM.
  parent,

  /// Imported from a BOM.
  bom,
}
