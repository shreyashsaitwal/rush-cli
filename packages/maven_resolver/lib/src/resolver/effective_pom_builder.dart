/// Effective POM builder.
///
/// Builds an effective POM by fetching the parent chain, processing
/// BOM imports, and interpolating all properties.
library;

import 'dart:convert';

import '../pom/dependency.dart';
import '../pom/pom.dart';
import '../pom/pom_interpolator.dart';
import '../pom/pom_parser.dart';
import '../repository/artifact_coordinate.dart';
import '../repository/repository.dart';
import '../repository/repository_exception.dart';
import 'resolution_context.dart';

/// Builds effective POMs by resolving parent chains and BOM imports.
///
/// This class handles:
/// - Fetching parent POMs recursively
/// - Processing BOM imports in dependencyManagement
/// - Interpolating all properties
/// - Following relocations
/// - Caching results to avoid redundant fetches
final class EffectivePomBuilder {
  /// The repository to fetch POMs from.
  final Repository repository;

  /// The POM parser.
  final PomParser _parser;

  /// The POM interpolator.
  final PomInterpolator _interpolator;

  /// Maximum parent chain depth (to prevent infinite loops).
  final int maxParentDepth;

  /// Maximum BOM import depth (to prevent infinite loops).
  final int maxBomDepth;

  /// Maximum relocation chain depth (to prevent infinite loops).
  final int maxRelocationDepth;

  /// Creates an effective POM builder.
  EffectivePomBuilder({
    required this.repository,
    PomParser? parser,
    PomInterpolator? interpolator,
    this.maxParentDepth = 20,
    this.maxBomDepth = 10,
    this.maxRelocationDepth = 5,
  })  : _parser = parser ?? const PomParser(),
        _interpolator = interpolator ?? PomInterpolator();

  /// Builds an effective POM for the given coordinate.
  ///
  /// This fetches the POM, resolves its parent chain, processes BOM imports,
  /// and interpolates all properties. If the POM contains a relocation,
  /// it follows the relocation to the new coordinates.
  ///
  /// The [context] is used for caching and error collection.
  /// The [bomDepth] tracks BOM import recursion depth.
  /// The [relocationDepth] tracks relocation chain depth.
  Future<EffectivePom?> build(
    ArtifactCoordinate coord,
    ResolutionContext context, {
    int bomDepth = 0,
    int relocationDepth = 0,
  }) async {
    final cacheKey = coord.toString();

    // Check cache first
    final cached = context.getCachedPom(cacheKey);
    if (cached != null) return cached;

    // Fetch the POM
    final pom = await _fetchPom(coord, context);
    if (pom == null) return null;

    // Check for relocation
    final relocation = pom.distributionManagement?.relocation;
    if (relocation != null && relocation.isEffective) {
      return _handleRelocation(
        coord,
        pom,
        relocation,
        context,
        bomDepth: bomDepth,
        relocationDepth: relocationDepth,
      );
    }

    // Build parent chain
    final parentChain = await _buildParentChain(pom, context);

    // Process BOM imports
    final bomDeps =
        await _processBomImports(pom, parentChain, context, bomDepth);

    // Interpolate
    final effectivePom = _interpolator.interpolate(
      pom,
      parentChain: parentChain,
    );

    // Add BOM-imported dependencies to dependencyManagement
    final mergedMgmt = _mergeDependencyManagement(
      effectivePom.dependencyManagement,
      bomDeps,
    );

    // Create final effective POM
    final result = EffectivePom(
      pom: effectivePom.pom,
      parentChain: effectivePom.parentChain,
      properties: effectivePom.properties,
      dependencyManagement: mergedMgmt,
    );

    // Cache it
    context.cachePom(cacheKey, result);

    return result;
  }

  /// Handles a relocated artifact by following to the new coordinates.
  ///
  /// Maven relocation works as follows:
  /// - groupId: If specified, use the new groupId; otherwise keep original
  /// - artifactId: If specified, use the new artifactId; otherwise keep original
  /// - version: If specified, use the new version; otherwise keep original
  Future<EffectivePom?> _handleRelocation(
    ArtifactCoordinate originalCoord,
    Pom originalPom,
    Relocation relocation,
    ResolutionContext context, {
    required int bomDepth,
    required int relocationDepth,
  }) async {
    if (relocationDepth >= maxRelocationDepth) {
      context.addError(
        ResolutionError(
          coordinate: originalCoord,
          message:
              'Relocation chain exceeds maximum depth of $maxRelocationDepth',
        ),
      );
      return null;
    }

    // Build the new coordinate from relocation
    final newCoord = ArtifactCoordinate(
      groupId: relocation.groupId ?? originalCoord.groupId,
      artifactId: relocation.artifactId ?? originalCoord.artifactId,
      version: relocation.version ?? originalCoord.version,
      packaging: originalCoord.packaging,
      classifier: originalCoord.classifier,
    );

    // Log the relocation if there's a message
    if (relocation.message != null) {
      context.addWarning(
        ResolutionWarning(
          coordinate: originalCoord,
          message: 'Artifact relocated to $newCoord: ${relocation.message}',
        ),
      );
    } else {
      context.addWarning(
        ResolutionWarning(
          coordinate: originalCoord,
          message: 'Artifact relocated to $newCoord',
        ),
      );
    }

    // Cache the original coordinate as pointing to the new one
    // This ensures subsequent requests for the old coordinate also get the new POM
    final result = await build(
      newCoord,
      context,
      bomDepth: bomDepth,
      relocationDepth: relocationDepth + 1,
    );

    if (result != null) {
      // Also cache under the original key so future lookups find it
      context.cachePom(originalCoord.toString(), result);
    }

    return result;
  }

  /// Fetches and parses a POM.
  Future<Pom?> _fetchPom(
    ArtifactCoordinate coord,
    ResolutionContext context,
  ) async {
    try {
      final result = await repository.fetchPom(coord);
      if (result == null) {
        context.addError(
          ResolutionError(
            coordinate: coord,
            message: 'POM not found in any repository',
          ),
        );
        return null;
      }

      final content = utf8.decode(result.content);
      return _parser.parseString(content);
    } on PomParseException catch (e, st) {
      context.addError(
        ResolutionError(
          coordinate: coord,
          message: 'Failed to parse POM: ${e.message}',
          cause: e,
          stackTrace: st,
        ),
      );
      return null;
    } on RepositoryException catch (e, st) {
      context.addError(
        ResolutionError(
          coordinate: coord,
          message: 'Failed to fetch POM: ${e.message}',
          cause: e,
          stackTrace: st,
        ),
      );
      return null;
    }
  }

  /// Builds the parent chain for a POM.
  Future<List<Pom>> _buildParentChain(
    Pom pom,
    ResolutionContext context, {
    int depth = 0,
  }) async {
    if (pom.parent == null) return [];
    if (depth >= maxParentDepth) {
      context.addError(
        ResolutionError(
          message: 'Parent chain exceeds maximum depth of $maxParentDepth',
        ),
      );
      return [];
    }

    final parentCoord = pom.parent!.coordinate;
    final parentPom = await _fetchPom(parentCoord, context);
    if (parentPom == null) return [];

    // Recursively build grandparent chain
    final grandparents = await _buildParentChain(
      parentPom,
      context,
      depth: depth + 1,
    );

    return [parentPom, ...grandparents];
  }

  /// Processes BOM imports in dependencyManagement.
  ///
  /// BOM imports are `<type>pom</type><scope>import</scope>` entries
  /// that import another POM's dependencyManagement.
  ///
  /// Maven BOM processing rules:
  /// 1. At the same level (same POM), first declared BOM wins
  /// 2. Child-level BOMs override parent-level BOMs
  /// 3. Local dependencyManagement declarations override all BOMs
  Future<List<Dependency>> _processBomImports(
    Pom pom,
    List<Pom> parentChain,
    ResolutionContext context,
    int bomDepth,
  ) async {
    if (bomDepth >= maxBomDepth) {
      context.addError(
        ResolutionError(
          message: 'BOM import chain exceeds maximum depth of $maxBomDepth',
        ),
      );
      return [];
    }

    // Process BOMs level by level. Within each level, first BOM wins.
    // Child levels override parent levels.
    //
    // We process from most distant ancestor to child POM, where each level
    // can override the previous. Within a level, we use putIfAbsent so
    // the first declaration wins.

    final resultMap = <String, Dependency>{};

    // Build list of levels: most distant ancestor first, child POM last
    // Each level is a list of BOM imports from that POM
    final levels = <List<Dependency>>[];
    for (final parent in parentChain.reversed) {
      levels.add(parent.bomImports);
    }
    levels.add(pom.bomImports);

    // Process each level
    for (final levelBoms in levels) {
      // Collect all entries from this level's BOMs
      // Within a level, first BOM's declaration wins (use putIfAbsent)
      final levelEntries = <String, Dependency>{};

      for (final bomImport in levelBoms) {
        if (bomImport.version == null) {
          context.addError(
            ResolutionError(
              message: 'BOM import missing version: ${bomImport.coordinate}',
            ),
          );
          continue;
        }

        final bomCoord = ArtifactCoordinate(
          groupId: bomImport.groupId,
          artifactId: bomImport.artifactId,
          version: bomImport.version!,
          packaging: 'pom',
        );

        // Recursively build the BOM's effective POM
        final bomEffective = await build(
          bomCoord,
          context,
          bomDepth: bomDepth + 1,
        );

        if (bomEffective != null) {
          // Within this level, first declaration wins
          for (final dep in bomEffective.dependencyManagement) {
            if (!dep.isBomImport) {
              levelEntries.putIfAbsent(dep.conflictKey, () => dep);
            }
          }
        }
      }

      // Child level overrides parent level (direct assignment)
      for (final entry in levelEntries.entries) {
        resultMap[entry.key] = entry.value;
      }
    }

    return resultMap.values.toList();
  }

  /// Merges local dependencyManagement with BOM-imported dependencies.
  ///
  /// Local declarations take precedence over BOM imports.
  List<Dependency> _mergeDependencyManagement(
    List<Dependency> local,
    List<Dependency> fromBoms,
  ) {
    final merged = <String, Dependency>{};

    // BOM imports first (already deduplicated with child overriding parent)
    for (final dep in fromBoms) {
      merged[dep.conflictKey] = dep;
    }

    // Local declarations override BOM imports
    for (final dep in local) {
      merged[dep.conflictKey] = dep;
    }

    return merged.values.toList();
  }
}
