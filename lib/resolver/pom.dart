import 'dart:convert';

import 'package:xml2json/xml2json.dart';

class Pom {
  final String artifactId;
  final String packaging;
  final Map<String, dynamic> properties;

  // The below two fields are not final because we might need to set them later
  // if they are null (null when this POM inherits from its parent).
  String? groupId;
  String? version;

  final Parent? parent;
  final Set<Dependency> dependencies;
  final Set<Dependency> dependencyManagement;

  String get coordinate => '$groupId:$artifactId:$version';

  Pom({
    required this.groupId,
    required this.artifactId,
    required this.version,
    required this.packaging,
    required this.properties,
    required this.parent,
    required this.dependencies,
    required this.dependencyManagement,
  });

  factory Pom.fromXml(String xmlString) {
    final transformer = Xml2Json()..parse(xmlString);
    final json =
        jsonDecode(transformer.toParker())['project'] as Map<String, dynamic>;

    return Pom(
      artifactId: json['artifactId'] as String,
      groupId: json['groupId'] != null ? json['groupId'] as String : null,
      version: json['version'] != null ? json['version'] as String : null,
      packaging:
          json['packaging'] != null ? json['packaging'] as String : 'jar',
      parent: json['parent'] != null
          ? Parent.fromJson(json['parent'] as Map<String, dynamic>)
          : null,
      properties: json['properties'] != null
          ? json['properties'] as Map<String, dynamic>
          : {},
      dependencies: _constructDependencies(json['dependencies'] as Map?),
      dependencyManagement: _constructDependencies(
          json['dependencyManagement']?['dependencies'] as Map?),
    );
  }

  static Set<Dependency> _constructDependencies(Map? map) {
    if (map == null || map.isEmpty) return <Dependency>{};

    final depTag = map['dependency'];
    if (depTag is Map) {
      return {Dependency.fromJson(depTag as Map<String, dynamic>)};
    } else {
      return (depTag as List)
          .map((dep) => Dependency.fromJson(dep as Map<String, dynamic>))
          .toSet();
    }
  }
}

class Parent {
  final String groupId;
  final String artifactId;
  final String version;

  String get coordinate => '$groupId:$artifactId:$version';

  Parent({
    required this.groupId,
    required this.artifactId,
    required this.version,
  });

  factory Parent.fromJson(Map<String, dynamic> json) => Parent(
        groupId: json['groupId'] as String,
        artifactId: json['artifactId'] as String,
        version: json['version'] as String,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Parent &&
          runtimeType == other.runtimeType &&
          groupId == other.groupId &&
          artifactId == other.artifactId &&
          version == other.version;

  @override
  int get hashCode => Object.hash(groupId, artifactId, version);
}

class Dependency {
  String? version;
  String? scope;
  final bool? optional;
  final String groupId;
  final String artifactId;

  String get coordinate => '$groupId:$artifactId:$version';

  Dependency({
    required this.groupId,
    required this.artifactId,
    this.version,
    this.optional,
    this.scope,
  });

  factory Dependency.fromJson(Map<String, dynamic> json) => Dependency(
        groupId: json['groupId'] as String,
        artifactId: json['artifactId'] as String,
        version: json['version'] as String?,
        optional: (json['optional'] as String?) == 'true',
        scope: json['scope'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Dependency &&
          runtimeType == other.runtimeType &&
          groupId == other.groupId &&
          artifactId == other.artifactId &&
          version == other.version &&
          optional == other.optional &&
          scope == other.scope;

  @override
  int get hashCode =>
      Object.hash(groupId, artifactId, version, optional, scope);
}
