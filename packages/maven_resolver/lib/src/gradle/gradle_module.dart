import 'dart:convert';

import '../pom/dependency.dart';
import '../pom/exclusion.dart';

List<Dependency>? platformVariantDependencies(String json) =>
    switch (jsonDecode(json)) {
      {'component': {'url': String _}, 'variants': final List<dynamic> variants}
          when _library(variants, 'java-runtime') != null =>
        _scoped(_library(variants, 'java-runtime')!,
            api: _library(variants, 'java-api') ?? const []),
      _ => null,
    };

List<Dependency> _scoped(List<Dependency> runtime,
    {required List<Dependency> api}) {
  final apiKeys = {for (final dependency in api) dependency.conflictKey};
  return [
    for (final dependency in runtime)
      dependency.copyWith(
        scope: apiKeys.contains(dependency.conflictKey)
            ? DependencyScope.compile
            : DependencyScope.runtime,
      ),
  ];
}

List<Dependency>? _library(List<dynamic> variants, String usage) {
  for (final variant in variants) {
    if (variant case {'attributes': final Map<String, dynamic> attributes}
        when attributes['org.gradle.usage'] == usage &&
            _isLibrary(attributes)) {
      return [
        if (variant['dependencies'] case final List<dynamic> dependencies)
          for (final dependency in dependencies)
            if (_dependency(dependency) case final parsed?) parsed,
      ];
    }
  }
  return null;
}

bool _isLibrary(Map<String, dynamic> attributes) =>
    (attributes['org.gradle.category'] ?? 'library') == 'library';

Dependency? _dependency(Object? dependency) => switch (dependency) {
      {'group': final String group, 'module': final String module} &&
              final Map<dynamic, dynamic> declared
          when _isLibrary(_attributes(declared)) =>
        Dependency(
          groupId: group,
          artifactId: module,
          version: _version(declared['version']),
          exclusions: [
            if (declared['excludes'] case final List<dynamic> excludes)
              for (final exclusion in excludes)
                if (exclusion
                    case {
                      'group': final String group,
                      'module': final String module
                    })
                  Exclusion(groupId: group, artifactId: module),
          ],
        ),
      _ => null,
    };

Map<String, dynamic> _attributes(Map<dynamic, dynamic> dependency) =>
    switch (dependency['attributes']) {
      final Map<String, dynamic> attributes => attributes,
      _ => const {},
    };

String? _version(Object? version) => switch (version) {
      {'strictly': final String strictly} => strictly,
      {'requires': final String requires} => requires,
      {'prefers': final String prefers} => prefers,
      _ => null,
    };
