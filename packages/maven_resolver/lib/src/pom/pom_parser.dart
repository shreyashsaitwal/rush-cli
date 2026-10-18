/// POM XML parser.
///
/// Parses Maven POM XML files into [Pom] objects.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'dependency.dart';
import 'exclusion.dart';
import 'pom.dart';

/// Exception thrown when POM parsing fails.
final class PomParseException implements Exception {
  /// The error message.
  final String message;

  /// The path to the POM file, if known.
  final String? path;

  /// The underlying cause, if any.
  final Object? cause;

  const PomParseException(this.message, {this.path, this.cause});

  @override
  String toString() {
    final buffer = StringBuffer('PomParseException: $message');
    if (path != null) {
      buffer.write(' (in $path)');
    }
    if (cause != null) {
      buffer.write('\nCaused by: $cause');
    }
    return buffer.toString();
  }
}

/// Parses Maven POM XML into [Pom] objects.
final class PomParser {
  const PomParser();

  /// Parses a POM from raw bytes.
  Pom parse(Uint8List content, {String? path}) {
    try {
      final xml = utf8.decode(content);
      return parseString(xml, path: path);
    } on FormatException catch (e) {
      throw PomParseException(
        'Invalid UTF-8 encoding',
        path: path,
        cause: e,
      );
    }
  }

  /// Parses a POM from an XML string.
  Pom parseString(String xml, {String? path}) {
    try {
      final document = XmlDocument.parse(xml);
      return parseDocument(document, path: path);
    } on XmlParserException catch (e) {
      throw PomParseException(
        'Invalid XML: ${e.message}',
        path: path,
        cause: e,
      );
    }
  }

  /// Parses a POM from an XML document.
  Pom parseDocument(XmlDocument document, {String? path}) {
    final root = document.rootElement;

    if (root.name.local != 'project') {
      throw PomParseException(
        'Expected <project> root element, got <${root.name.local}>',
        path: path,
      );
    }

    return _parseProject(root, path: path);
  }

  Pom _parseProject(XmlElement project, {String? path}) {
    final modelVersion = _text(project, 'modelVersion');
    final groupId = _text(project, 'groupId');
    final artifactId = _text(project, 'artifactId');
    final version = _text(project, 'version');
    final packaging = _text(project, 'packaging') ?? 'jar';
    final name = _text(project, 'name');
    final description = _text(project, 'description');
    final url = _text(project, 'url');

    if (artifactId == null) {
      throw PomParseException('Missing required <artifactId>', path: path);
    }

    final parent = _parseParent(project.getElement('parent'));
    final properties = _parseProperties(project.getElement('properties'));
    final dependencies = _parseDependencies(project.getElement('dependencies'));
    final dependencyManagement = _parseDependencyManagement(
      project.getElement('dependencyManagement'),
    );
    final modules = _parseModules(project.getElement('modules'));
    final licenses = _parseLicenses(project.getElement('licenses'));
    final scm = _parseScm(project.getElement('scm'));
    final distributionManagement = _parseDistributionManagement(
      project.getElement('distributionManagement'),
    );

    return Pom(
      modelVersion: modelVersion,
      groupId: groupId,
      artifactId: artifactId,
      version: version,
      packaging: packaging,
      name: name,
      description: description,
      url: url,
      parent: parent,
      properties: properties,
      dependencies: dependencies,
      dependencyManagement: dependencyManagement,
      modules: modules,
      licenses: licenses,
      scm: scm,
      distributionManagement: distributionManagement,
    );
  }

  ParentRef? _parseParent(XmlElement? element) {
    if (element == null) return null;

    final groupId = _text(element, 'groupId');
    final artifactId = _text(element, 'artifactId');
    final version = _text(element, 'version');
    final relativePath = _text(element, 'relativePath') ?? '../pom.xml';

    if (groupId == null || artifactId == null || version == null) {
      return null; // Invalid parent, skip
    }

    return ParentRef(
      groupId: groupId,
      artifactId: artifactId,
      version: version,
      relativePath: relativePath,
    );
  }

  Map<String, String> _parseProperties(XmlElement? element) {
    if (element == null) return const {};

    final properties = <String, String>{};
    for (final child in element.childElements) {
      final name = child.name.local;
      final value = child.innerText;
      properties[name] = value;
    }
    return properties;
  }

  List<Dependency> _parseDependencies(XmlElement? element) {
    if (element == null) return const [];

    return element
        .findElements('dependency')
        .map(_parseDependency)
        .whereType<Dependency>()
        .toList();
  }

  Dependency? _parseDependency(XmlElement element) {
    final groupId = _text(element, 'groupId');
    final artifactId = _text(element, 'artifactId');

    if (groupId == null || artifactId == null) {
      return null; // Invalid dependency, skip
    }

    final version = _text(element, 'version');
    final type = _text(element, 'type') ?? 'jar';
    final classifier = _text(element, 'classifier');
    final scopeStr = _text(element, 'scope');
    final scope = DependencyScope.parse(scopeStr);
    final scopeExplicit = scopeStr != null; // Track if scope was explicitly set
    final systemPath = _text(element, 'systemPath');
    final optionalStr = _text(element, 'optional');
    final optional = optionalStr?.toLowerCase() == 'true';
    final exclusions = _parseExclusions(element.getElement('exclusions'));

    return Dependency(
      groupId: groupId,
      artifactId: artifactId,
      version: version,
      type: type,
      classifier: classifier,
      scope: scope,
      scopeExplicit: scopeExplicit,
      systemPath: systemPath,
      optional: optional,
      exclusions: exclusions,
    );
  }

  List<Exclusion> _parseExclusions(XmlElement? element) {
    if (element == null) return const [];

    return element
        .findElements('exclusion')
        .map(_parseExclusion)
        .whereType<Exclusion>()
        .toList();
  }

  Exclusion? _parseExclusion(XmlElement element) {
    final groupId = _text(element, 'groupId');
    final artifactId = _text(element, 'artifactId');

    if (groupId == null || artifactId == null) {
      return null; // Invalid exclusion, skip
    }

    return Exclusion(groupId: groupId, artifactId: artifactId);
  }

  List<Dependency> _parseDependencyManagement(XmlElement? element) {
    if (element == null) return const [];

    final dependencies = element.getElement('dependencies');
    if (dependencies == null) return const [];

    return _parseDependencies(dependencies);
  }

  List<String> _parseModules(XmlElement? element) {
    if (element == null) return const [];

    return element
        .findElements('module')
        .map((e) => e.innerText)
        .where((s) => s.isNotEmpty)
        .toList();
  }

  List<License> _parseLicenses(XmlElement? element) {
    if (element == null) return const [];

    return element.findElements('license').map(_parseLicense).toList();
  }

  License _parseLicense(XmlElement element) {
    return License(
      name: _text(element, 'name'),
      url: _text(element, 'url'),
      distribution: _text(element, 'distribution'),
      comments: _text(element, 'comments'),
    );
  }

  Scm? _parseScm(XmlElement? element) {
    if (element == null) return null;

    return Scm(
      connection: _text(element, 'connection'),
      developerConnection: _text(element, 'developerConnection'),
      url: _text(element, 'url'),
      tag: _text(element, 'tag'),
    );
  }

  DistributionManagement? _parseDistributionManagement(XmlElement? element) {
    if (element == null) return null;

    final relocation = _parseRelocation(element.getElement('relocation'));

    if (relocation == null) return null;

    return DistributionManagement(relocation: relocation);
  }

  Relocation? _parseRelocation(XmlElement? element) {
    if (element == null) return null;

    return Relocation(
      groupId: _text(element, 'groupId'),
      artifactId: _text(element, 'artifactId'),
      version: _text(element, 'version'),
      message: _text(element, 'message'),
    );
  }

  /// Gets the text content of a child element.
  String? _text(XmlElement parent, String name) {
    final child = parent.getElement(name);
    if (child == null) return null;
    final text = child.innerText.trim();
    return text.isEmpty ? null : text;
  }
}
