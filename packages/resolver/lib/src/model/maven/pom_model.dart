import 'dart:convert';

import 'package:xml2json/xml2json.dart';

class PomModel {
  final String groupId;
  final String artifactId;
  final String version;
  final String name;
  final String description;
  final String url;
  final Parent? parent;
  final String packaging;
  final List<Dependency> dependencies;
  final Map<String, dynamic> properties;

  PomModel({
    required this.artifactId,
    required this.groupId,
    required this.version,
    required this.name,
    required this.packaging,
    required this.description,
    required this.url,
    required this.dependencies,
    required this.properties,
    required this.parent,
  });

  factory PomModel.fromXml(String xmlString) {
    final transformer = Xml2Json()..parse(xmlString);
    final json = jsonDecode(transformer.toParker());
    return PomModel._fromJson(json['project']);
  }

  factory PomModel._fromJson(Map<String, dynamic> json) => PomModel(
        artifactId: json['artifactId'] as String,
        groupId:
            json['groupId'] as String? ?? json['parent']['groupId'] as String,
        version: (json['version'] ?? json['parent']['version']) as String,
        name: json['name'] as String? ?? '',
        packaging: json['packaging'] as String? ?? 'jar',
        description: json['description'] as String? ?? '',
        url: json['url'] as String? ?? '',
        properties: json['properties'] ?? <String, dynamic>{},
        dependencies: json['dependencies'] == null
            ? const []
            : PomModel._depFromJson(
                json['dependencies'] as Map<String, dynamic>,
                json['properties']),
        parent: json['parent'] != null ? Parent._fromJson(json['parent']) : null,
      );

  static List<Dependency> _depFromJson(
      Map<String, dynamic> json, Map<String, dynamic>? properties) {
    final deps = <Dependency>[];
    final jsonDeps = json['dependency'];

    // If the artifact has only one dep, it will be decoded as a map instead of
    // a list.
    if (jsonDeps is Map) {
      deps.add(
          Dependency._fromJson(jsonDeps as Map<String, dynamic>, properties));
    } else {
      for (final dep in jsonDeps) {
        deps.add(Dependency._fromJson(dep, properties));
      }
    }
    return deps;
  }
}

class Parent {
  final String groupId;
  final String artifactId;
  final String version;
  final List<Map<String, String>> properties;

  Parent({
    required this.groupId,
    required this.artifactId,
    required this.version,
    required this.properties,
  });

  factory Parent._fromJson(Map<String, dynamic> json) => Parent(
        groupId: json['groupId'] as String,
        artifactId: json['artifactId'] as String,
        version: json['version'] as String,
        properties: json['properties'] ?? const [],
      );

  String get coordinate => '$groupId:$artifactId:$version';
}

class Dependency {
  String groupId;
  String artifactId;
  String? version;
  String packaging;
  final DependencyScope scope;
  final bool optional;

  Dependency({
    required this.groupId,
    required this.artifactId,
    required this.version,
    required this.packaging,
    required this.scope,
    required this.optional,
  });

  factory Dependency._fromJson(Map<String, dynamic> json,
          [Map<String, dynamic>? properties]) =>
      Dependency(
        groupId: json['groupId'] as String,
        artifactId: json['artifactId'] as String,
        version: json['version'] as String?,
        packaging: json['packaging'] as String? ?? 'jar',
        scope: _scopeFromString(json['scope']),
        optional: json['optional'] == null
            ? false
            : Dependency._optionalFromJson(json['optional'] as String),
      );

  static bool _optionalFromJson(String optional) =>
      optional.toLowerCase() == 'true';

  static DependencyScope _scopeFromString(String? scope) {
    switch (scope) {
      case 'compile':
        return DependencyScope.compile;
      case 'provided':
        return DependencyScope.provided;
      case 'runtime':
        return DependencyScope.runtime;
      case 'test':
        return DependencyScope.test;
      default:
        return DependencyScope.compile;
    }
  }

  String get coordinate => '$groupId:$artifactId:$version';
}

enum DependencyScope {
  compile,
  provided,
  runtime,
  test,
}
