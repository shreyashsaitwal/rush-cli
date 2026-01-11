/// POM property interpolation.
///
/// Resolves property placeholders like `${project.version}` in POM values.
library;

import 'dart:io';

import 'dependency.dart';
import 'pom.dart';

/// Interpolates property placeholders in POM values.
///
/// Property resolution order:
/// 1. Project-defined properties (child overrides parent)
/// 2. Project fields (${project.version}, ${project.groupId}, etc.)
/// 3. Environment variables (${env.HOME})
///
/// Properties can reference other properties, which are resolved recursively.
/// Circular references are detected and left unresolved.
final class PomInterpolator {
  /// Maximum depth for recursive property resolution.
  final int maxDepth;

  const PomInterpolator({this.maxDepth = 10});

  /// Interpolates all property placeholders in a POM.
  ///
  /// [pom] is the POM to interpolate.
  /// [parentChain] is the list of parent POMs (nearest first).
  /// [additionalProperties] are extra properties to include.
  EffectivePom interpolate(
    Pom pom, {
    List<Pom> parentChain = const [],
    Map<String, String> additionalProperties = const {},
  }) {
    // Build the merged property map
    final properties =
        _buildPropertyMap(pom, parentChain, additionalProperties);

    // Build merged dependencyManagement
    final dependencyManagement = _buildDependencyManagement(pom, parentChain);

    // Create project context for ${project.*} properties
    final projectContext = _ProjectContext(pom: pom, parentChain: parentChain);

    // Interpolate dependencies
    final interpolatedDeps = pom.dependencies
        .map((d) => _interpolateDependency(d, properties, projectContext))
        .toList();

    // Interpolate dependencyManagement
    final interpolatedMgmt = dependencyManagement
        .map((d) => _interpolateDependency(d, properties, projectContext))
        .toList();

    // Create interpolated POM
    final interpolatedPom = pom.copyWith(
      groupId: _interpolateValue(
        pom.groupId ?? pom.parent?.groupId,
        properties,
        projectContext,
      ),
      version: _interpolateValue(
        pom.version ?? pom.parent?.version,
        properties,
        projectContext,
      ),
      name: _interpolateValue(pom.name, properties, projectContext),
      description:
          _interpolateValue(pom.description, properties, projectContext),
      url: _interpolateValue(pom.url, properties, projectContext),
      dependencies: interpolatedDeps,
      dependencyManagement: interpolatedMgmt,
    );

    return EffectivePom(
      pom: interpolatedPom,
      parentChain: parentChain,
      properties: properties,
      dependencyManagement: interpolatedMgmt,
    );
  }

  /// Interpolates a single value with the given properties.
  String? interpolateValue(
    String? value,
    Map<String, String> properties, {
    Pom? pom,
    List<Pom> parentChain = const [],
  }) {
    if (value == null) return null;
    final projectContext = pom != null
        ? _ProjectContext(pom: pom, parentChain: parentChain)
        : null;
    return _interpolateValue(value, properties, projectContext);
  }

  /// Builds the merged property map from POM and parent chain.
  ///
  /// Properties are merged with child values overriding parent values.
  Map<String, String> _buildPropertyMap(
    Pom pom,
    List<Pom> parentChain,
    Map<String, String> additionalProperties,
  ) {
    final properties = <String, String>{};

    // Start with most distant ancestor (reverse order)
    for (final parent in parentChain.reversed) {
      properties.addAll(parent.properties);
    }

    // Child properties override parent properties
    properties.addAll(pom.properties);

    // Additional properties (from settings, etc.) have lowest priority
    // They should not override POM properties
    for (final entry in additionalProperties.entries) {
      properties.putIfAbsent(entry.key, () => entry.value);
    }

    return properties;
  }

  /// Builds merged dependencyManagement from POM and parent chain.
  ///
  /// Child entries override parent entries for the same artifact.
  List<Dependency> _buildDependencyManagement(
    Pom pom,
    List<Pom> parentChain,
  ) {
    final managedDeps = <String, Dependency>{};

    // Start with most distant ancestor
    for (final parent in parentChain.reversed) {
      for (final dep in parent.dependencyManagement) {
        // Skip BOM imports - they should be processed separately
        if (!dep.isBomImport) {
          managedDeps[dep.conflictKey] = dep;
        }
      }
    }

    // Child entries override parent entries
    for (final dep in pom.dependencyManagement) {
      if (!dep.isBomImport) {
        managedDeps[dep.conflictKey] = dep;
      }
    }

    return managedDeps.values.toList();
  }

  Dependency _interpolateDependency(
    Dependency dep,
    Map<String, String> properties,
    _ProjectContext? projectContext,
  ) {
    return Dependency(
      groupId: _interpolateValue(dep.groupId, properties, projectContext) ??
          dep.groupId,
      artifactId:
          _interpolateValue(dep.artifactId, properties, projectContext) ??
              dep.artifactId,
      version: _interpolateValue(dep.version, properties, projectContext),
      type: _interpolateValue(dep.type, properties, projectContext) ?? dep.type,
      classifier: _interpolateValue(dep.classifier, properties, projectContext),
      scope: dep.scope,
      systemPath: _interpolateValue(dep.systemPath, properties, projectContext),
      optional: dep.optional,
      exclusions: dep.exclusions,
    );
  }

  String? _interpolateValue(
    String? value,
    Map<String, String> properties,
    _ProjectContext? projectContext,
  ) {
    if (value == null) return null;
    if (!value.contains('\$')) return value;

    return _resolveProperties(value, properties, projectContext, {}, 0);
  }

  /// Resolves all property placeholders in a value.
  String _resolveProperties(
    String value,
    Map<String, String> properties,
    _ProjectContext? projectContext,
    Set<String> resolving, // For cycle detection
    int depth,
  ) {
    if (depth > maxDepth) return value;

    // Match ${property.name} patterns
    final pattern = RegExp(r'\$\{([^}]+)\}');

    return value.replaceAllMapped(pattern, (match) {
      final propertyName = match.group(1)!;

      // Check for circular reference
      if (resolving.contains(propertyName)) {
        return match.group(0)!; // Leave unresolved
      }

      final resolved = _resolveProperty(
        propertyName,
        properties,
        projectContext,
        {...resolving, propertyName},
        depth + 1,
      );

      return resolved ?? match.group(0)!;
    });
  }

  /// Resolves a single property name.
  String? _resolveProperty(
    String name,
    Map<String, String> properties,
    _ProjectContext? projectContext,
    Set<String> resolving,
    int depth,
  ) {
    // 1. Check user-defined properties
    if (properties.containsKey(name)) {
      final value = properties[name]!;
      // Recursively resolve if the value contains properties
      if (value.contains('\$')) {
        return _resolveProperties(
            value, properties, projectContext, resolving, depth);
      }
      return value;
    }

    // 2. Check project.* properties
    if (name.startsWith('project.') && projectContext != null) {
      final projectProp = _resolveProjectProperty(name, projectContext);
      if (projectProp != null) {
        if (projectProp.contains('\$')) {
          return _resolveProperties(
              projectProp, properties, projectContext, resolving, depth);
        }
        return projectProp;
      }
    }

    // 3. Check pom.* (alias for project.*)
    if (name.startsWith('pom.') && projectContext != null) {
      final projectName = 'project.${name.substring(4)}';
      final projectProp = _resolveProjectProperty(projectName, projectContext);
      if (projectProp != null) return projectProp;
    }

    // 4. Check env.* properties
    if (name.startsWith('env.')) {
      final envName = name.substring(4);
      final envValue = Platform.environment[envName];
      if (envValue != null) return envValue;
    }

    // 5. Not found
    return null;
  }

  /// Resolves a project.* property.
  String? _resolveProjectProperty(String name, _ProjectContext context) {
    final pom = context.pom;
    final parent = pom.parent;

    return switch (name) {
      'project.groupId' => pom.groupId ?? parent?.groupId,
      'project.artifactId' => pom.artifactId,
      'project.version' => pom.version ?? parent?.version,
      'project.packaging' => pom.packaging,
      'project.name' => pom.name,
      'project.description' => pom.description,
      'project.url' => pom.url,
      'project.parent.groupId' => parent?.groupId,
      'project.parent.artifactId' => parent?.artifactId,
      'project.parent.version' => parent?.version,
      _ => null,
    };
  }
}

/// Context for resolving project.* properties.
class _ProjectContext {
  final Pom pom;
  final List<Pom> parentChain;

  const _ProjectContext({
    required this.pom,
    this.parentChain = const [],
  });
}

/// Applies dependencyManagement to dependencies.
///
/// This fills in missing version, scope, exclusions from managed entries.
final class DependencyManagementApplier {
  const DependencyManagementApplier();

  /// Applies management to a list of dependencies.
  List<Dependency> apply(
    List<Dependency> dependencies,
    List<Dependency> management,
  ) {
    final managementMap = <String, Dependency>{};
    for (final dep in management) {
      managementMap[dep.conflictKey] = dep;
    }

    return dependencies.map((dep) {
      final managed = managementMap[dep.conflictKey];
      if (managed == null) return dep;
      return _applyManagement(dep, managed);
    }).toList();
  }

  Dependency _applyManagement(Dependency dep, Dependency managed) {
    return Dependency(
      groupId: dep.groupId,
      artifactId: dep.artifactId,
      // Version from dep if specified, otherwise from managed
      version: dep.version ?? managed.version,
      // Type from dep if not default, otherwise from managed
      type: dep.type != 'jar' ? dep.type : managed.type,
      // Classifier from dep if specified, otherwise from managed
      classifier: dep.classifier ?? managed.classifier,
      // Scope from dep if specified, otherwise from managed
      scope: dep.scope,
      systemPath: dep.systemPath ?? managed.systemPath,
      optional: dep.optional,
      // Merge exclusions
      exclusions: [...dep.exclusions, ...managed.exclusions],
    );
  }
}
