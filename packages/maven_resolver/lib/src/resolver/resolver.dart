/// Maven dependency resolver.
///
/// Implements breadth-first dependency resolution with:
/// - "Nearest wins" conflict resolution
/// - Scope mediation for transitive dependencies
/// - Exclusion filtering
/// - Optional dependency handling
/// - dependencyManagement support
library;

import 'dart:collection';

import '../pom/dependency.dart';
import '../pom/exclusion.dart';
import '../pom/pom_interpolator.dart';
import '../repository/artifact_coordinate.dart';
import '../repository/repository.dart';
import '../version/version_range.dart';
import 'dependency_node.dart';
import 'effective_pom_builder.dart';
import 'resolution_context.dart';

/// Configuration for the dependency resolver.
final class ResolverConfig {
  /// Whether to include optional dependencies.
  final bool includeOptional;

  /// The scopes to resolve.
  final Set<DependencyScope> scopes;

  /// Maximum resolution depth.
  final int maxDepth;

  /// Whether to fail on missing dependencies.
  final bool failOnMissing;

  const ResolverConfig({
    this.includeOptional = false,
    this.scopes = const {
      DependencyScope.compile,
      DependencyScope.runtime,
      DependencyScope.provided,
    },
    this.maxDepth = 50,
    this.failOnMissing = false,
  });

  /// Default configuration for compile classpath.
  static const compile = ResolverConfig();

  /// Configuration for runtime classpath.
  static const runtime = ResolverConfig(
    scopes: {DependencyScope.compile, DependencyScope.runtime},
  );

  /// Configuration for test classpath.
  static const test = ResolverConfig(
    scopes: {
      DependencyScope.compile,
      DependencyScope.runtime,
      DependencyScope.provided,
      DependencyScope.test,
    },
  );
}

/// A pending dependency to be resolved.
final class _PendingDependency {
  final Dependency dependency;
  final int depth;
  final List<String> path;
  final DependencyScope parentScope;

  /// Exclusions inherited from parent that apply to THIS dependency.
  final ExclusionSet parentExclusions;

  /// Exclusions to apply to this dependency's children (includes its own declared exclusions).
  final ExclusionSet childExclusions;

  const _PendingDependency({
    required this.dependency,
    required this.depth,
    required this.path,
    required this.parentScope,
    required this.parentExclusions,
    required this.childExclusions,
  });

  String get conflictKey => dependency.conflictKey;
}

/// Maven dependency resolver.
///
/// This is the main entry point for resolving Maven dependencies.
/// It uses breadth-first traversal to implement "nearest wins" semantics.
final class DependencyResolver {
  /// The repository to fetch from.
  final Repository repository;

  /// The effective POM builder.
  final EffectivePomBuilder _pomBuilder;

  /// The dependency management applier.
  final DependencyManagementApplier _mgmtApplier;

  /// The resolver configuration.
  final ResolverConfig config;

  /// Creates a dependency resolver.
  DependencyResolver({
    required this.repository,
    EffectivePomBuilder? pomBuilder,
    DependencyManagementApplier? mgmtApplier,
    this.config = ResolverConfig.compile,
  })  : _pomBuilder = pomBuilder ?? EffectivePomBuilder(repository: repository),
        _mgmtApplier = mgmtApplier ?? const DependencyManagementApplier();

  /// Resolves dependencies starting from the given direct dependencies.
  ///
  /// The [directDependencies] are the dependencies declared in the project.
  /// The [dependencyManagement] provides version/config templates.
  /// The [exclusions] are global exclusions to apply.
  Future<ResolutionResult> resolve({
    required List<Dependency> directDependencies,
    List<Dependency> dependencyManagement = const [],
    List<Exclusion> exclusions = const [],
  }) async {
    final context = ResolutionContext();

    // Initialize dependencyManagement
    context.addManagedDependencies(dependencyManagement);

    // Apply dependencyManagement to direct dependencies
    final managedDirect = _mgmtApplier.apply(
      directDependencies,
      dependencyManagement,
    );

    // Global exclusion set
    final globalExclusions = ExclusionSet(exclusions);

    // Build root nodes and resolved artifacts
    final roots = <DependencyNode>[];

    // BFS queue
    final queue = Queue<_PendingDependency>();

    // Enqueue direct dependencies
    for (final dep in managedDirect) {
      // Skip BOM imports - they're handled in dependencyManagement
      if (dep.isBomImport) continue;

      // NOTE: Direct optional dependencies are INCLUDED because the user
      // explicitly declared them. Only transitive optional deps are excluded.

      // Check scope
      if (!config.scopes.contains(dep.scope)) continue;

      // Check if excluded by global exclusions
      if (globalExclusions.matches(dep.groupId, dep.artifactId)) continue;

      // Record declaration order
      context.recordDeclaration(dep.conflictKey);

      queue.add(
        _PendingDependency(
          dependency: dep,
          depth: 1,
          path: [],
          parentScope: dep.scope,
          // For direct deps, the exclusions they declare apply to their children only
          // (merged with global exclusions)
          childExclusions: globalExclusions.merge(dep.exclusions),
          // Parent exclusions that apply to THIS dep are just global exclusions
          parentExclusions: globalExclusions,
        ),
      );
    }

    // Track pending versions for conflict detection
    final pendingVersions = <String, List<_VersionCandidate>>{};

    // Process queue breadth-first
    while (queue.isNotEmpty) {
      final pending = queue.removeFirst();

      // Check depth limit
      if (pending.depth > config.maxDepth) continue;

      // Check if excluded by PARENT exclusions (not our own declared exclusions)
      if (pending.parentExclusions.matches(
        pending.dependency.groupId,
        pending.dependency.artifactId,
      )) {
        continue;
      }

      // Resolve version if it's a range
      final version = await _resolveVersion(pending.dependency, context);
      if (version == null) {
        if (config.failOnMissing) {
          context.addError(
            ResolutionError(
              message: 'Cannot resolve version for ${pending.dependency}',
            ),
          );
        }
        continue;
      }

      final coord = ArtifactCoordinate(
        groupId: pending.dependency.groupId,
        artifactId: pending.dependency.artifactId,
        version: version,
        packaging: pending.dependency.type,
        classifier: pending.dependency.classifier,
      );

      final key = pending.conflictKey;
      final path = [...pending.path, coord.toString()];

      // Track this version as a candidate
      pendingVersions.putIfAbsent(key, () => []).add(
            _VersionCandidate(
              version: version,
              depth: pending.depth,
              declarationOrder: context.declarationOrder[key] ?? 0,
            ),
          );

      // Check if already resolved at a shallower depth
      if (!context.shouldResolve(key, pending.depth)) {
        continue;
      }

      // Avoid cycles
      if (context.isProcessing(key)) continue;
      context.processing.add(key);

      try {
        // Fetch and parse the POM
        final effectivePom = await _pomBuilder.build(coord, context);
        if (effectivePom == null) {
          context.processing.remove(key);
          continue;
        }

        // Add this POM's dependencyManagement to the context
        context.addManagedDependencies(effectivePom.dependencyManagement);

        // Use the effective POM's coordinate (may differ due to relocation)
        // but preserve the original classifier if any
        final effectiveCoord = ArtifactCoordinate(
          groupId: effectivePom.groupId,
          artifactId: effectivePom.artifactId,
          version: effectivePom.version,
          packaging: effectivePom.packaging,
          classifier: coord.classifier,
        );

        // Create the node with the effective (possibly relocated) coordinate
        final node = DependencyNode(
          coordinate: effectiveCoord,
          scope: pending.parentScope,
          optional: pending.dependency.optional,
          depth: pending.depth,
          path: path,
          exclusions: pending.childExclusions,
        );

        // Register as resolved
        context.addResolved(ResolvedArtifact.fromNode(node));

        // Add to roots if depth 1
        if (pending.depth == 1) {
          roots.add(node);
        }

        // Enqueue transitive dependencies
        for (final transitive in effectivePom.dependencies) {
          // Skip optional transitives
          if (transitive.optional && !config.includeOptional) continue;

          // Skip BOM imports
          if (transitive.isBomImport) continue;

          // Mediate scope
          final mediatedScope = mediateScope(
            pending.parentScope,
            transitive.scope,
          );
          if (mediatedScope == null) continue; // Omitted

          // Check scope configuration
          if (!config.scopes.contains(mediatedScope)) continue;

          // Apply dependencyManagement
          final managed = _applyManagement(transitive, context);

          // The child's parent exclusions are our child exclusions
          final transitiveParentExclusions = pending.childExclusions;
          // The child's child exclusions include its own declared exclusions
          final transitiveChildExclusions =
              transitiveParentExclusions.merge(transitive.exclusions);

          // Record declaration order
          context.recordDeclaration(managed.conflictKey);

          queue.add(
            _PendingDependency(
              dependency: managed.copyWith(scope: mediatedScope),
              depth: pending.depth + 1,
              path: path,
              parentScope: mediatedScope,
              parentExclusions: transitiveParentExclusions,
              childExclusions: transitiveChildExclusions,
            ),
          );
        }
      } finally {
        context.processing.remove(key);
      }
    }

    // Resolve version conflicts
    _resolveConflicts(pendingVersions, context);

    // Build final result
    return ResolutionResult(
      artifacts: context.resolved.values.toList(),
      roots: roots,
      conflicts: context.conflicts,
      warnings: context.warnings,
      errors: context.errors,
    );
  }

  /// Resolves a dependency version, handling ranges and dependencyManagement.
  Future<String?> _resolveVersion(
    Dependency dep,
    ResolutionContext context,
  ) async {
    // Check dependencyManagement first
    final managed = context.getManagedDependency(dep.conflictKey);
    final versionSpec = dep.version ?? managed?.version;

    if (versionSpec == null) {
      return null;
    }

    // Check if it's a range
    if (_isVersionRange(versionSpec)) {
      return _resolveVersionRange(dep, versionSpec, context);
    }

    return versionSpec;
  }

  /// Checks if a version string is a range.
  bool _isVersionRange(String version) {
    return version.startsWith('[') ||
        version.startsWith('(') ||
        version.contains(',');
  }

  /// Resolves a version range to a concrete version.
  Future<String?> _resolveVersionRange(
    Dependency dep,
    String rangeSpec,
    ResolutionContext context,
  ) async {
    try {
      final range = VersionRange.parse(rangeSpec);

      // Fetch available versions
      final available = await repository.listVersions(
        dep.groupId,
        dep.artifactId,
      );

      if (available.isEmpty) {
        context.addError(
          ResolutionError(
            message: 'No versions found for ${dep.groupId}:${dep.artifactId}',
          ),
        );
        return null;
      }

      // Select best version from range
      final best = range.selectBest(available);
      if (best == null) {
        context.addError(
          ResolutionError(
            message: 'No version satisfies range $rangeSpec for '
                '${dep.groupId}:${dep.artifactId}. '
                'Available: ${available.join(", ")}',
          ),
        );
        return null;
      }

      return best.toString();
    } on FormatException catch (e) {
      context.addError(
        ResolutionError(
          message: 'Invalid version range "$rangeSpec": ${e.message}',
        ),
      );
      return null;
    }
  }

  /// Applies dependencyManagement to a dependency.
  ///
  /// In Maven, dependencyManagement versions OVERRIDE transitive dependency
  /// versions, not just provide defaults for missing versions.
  Dependency _applyManagement(Dependency dep, ResolutionContext context) {
    final managed = context.getManagedDependency(dep.conflictKey);
    if (managed == null) return dep;

    return dep.copyWith(
      // dependencyManagement version takes precedence over transitive version
      version: managed.version ?? dep.version,
      exclusions: [...dep.exclusions, ...managed.exclusions],
    );
  }

  /// Resolves version conflicts using "nearest wins" strategy.
  void _resolveConflicts(
    Map<String, List<_VersionCandidate>> pendingVersions,
    ResolutionContext context,
  ) {
    for (final entry in pendingVersions.entries) {
      final key = entry.key;
      final candidates = entry.value;

      if (candidates.length <= 1) continue;

      // Group by version
      final byVersion = <String, _VersionCandidate>{};
      for (final candidate in candidates) {
        if (!byVersion.containsKey(candidate.version) ||
            _isBetterCandidate(candidate, byVersion[candidate.version]!)) {
          byVersion[candidate.version] = candidate;
        }
      }

      if (byVersion.length <= 1) continue;

      // Find the winner
      final sorted = byVersion.values.toList()
        ..sort((a, b) {
          // First by depth (nearer wins)
          final depthCmp = a.depth.compareTo(b.depth);
          if (depthCmp != 0) return depthCmp;
          // Then by declaration order (first wins)
          return a.declarationOrder.compareTo(b.declarationOrder);
        });

      final winner = sorted.first;
      final losers = sorted.skip(1).map((c) => c.version).toList();

      // Record conflict
      context.addConflict(
        ResolutionConflict(
          artifactKey: key,
          selectedVersion: winner.version,
          conflictingVersions: losers,
          depthByVersion: {
            for (final c in byVersion.values) c.version: c.depth,
          },
          reason: winner.depth < sorted[1].depth
              ? ConflictResolutionReason.nearestWins
              : ConflictResolutionReason.firstDeclaration,
        ),
      );
    }
  }

  /// Checks if candidate a is better than candidate b.
  bool _isBetterCandidate(_VersionCandidate a, _VersionCandidate b) {
    if (a.depth != b.depth) return a.depth < b.depth;
    return a.declarationOrder < b.declarationOrder;
  }
}

/// A version candidate during resolution.
final class _VersionCandidate {
  final String version;
  final int depth;
  final int declarationOrder;

  const _VersionCandidate({
    required this.version,
    required this.depth,
    required this.declarationOrder,
  });
}
