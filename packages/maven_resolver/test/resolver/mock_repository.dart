/// Mock repository for testing.
///
/// Allows defining POMs and artifacts in-memory for unit tests.
library;

import 'dart:typed_data';

import 'package:maven_resolver/maven_resolver.dart';

/// A mock repository that serves POMs from an in-memory map.
class MockRepository implements Repository {
  /// POMs keyed by coordinate string (group:artifact:version).
  final Map<String, String> poms = {};

  /// Available versions for each artifact (group:artifact -> versions).
  final Map<String, List<String>> versions = {};

  @override
  final String id;

  @override
  String get location => 'mock://test';

  MockRepository({this.id = 'mock'});

  /// Adds a POM to the repository.
  void addPom(
    String groupId,
    String artifactId,
    String version,
    String pomXml,
  ) {
    final key = '$groupId:$artifactId:$version';
    poms[key] = pomXml;

    // Also track version
    final versionKey = '$groupId:$artifactId';
    versions.putIfAbsent(versionKey, () => []).add(version);
  }

  /// Creates a simple POM with the given dependencies.
  void addSimplePom(
    String groupId,
    String artifactId,
    String version, {
    List<String> dependencies = const [],
    String? parentGroupId,
    String? parentArtifactId,
    String? parentVersion,
    Map<String, String> properties = const {},
  }) {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<project>');
    buffer.writeln('  <modelVersion>4.0.0</modelVersion>');

    if (parentGroupId != null) {
      buffer.writeln('  <parent>');
      buffer.writeln('    <groupId>$parentGroupId</groupId>');
      buffer.writeln('    <artifactId>$parentArtifactId</artifactId>');
      buffer.writeln('    <version>$parentVersion</version>');
      buffer.writeln('  </parent>');
    }

    buffer.writeln('  <groupId>$groupId</groupId>');
    buffer.writeln('  <artifactId>$artifactId</artifactId>');
    buffer.writeln('  <version>$version</version>');

    if (properties.isNotEmpty) {
      buffer.writeln('  <properties>');
      for (final entry in properties.entries) {
        buffer.writeln('    <${entry.key}>${entry.value}</${entry.key}>');
      }
      buffer.writeln('  </properties>');
    }

    if (dependencies.isNotEmpty) {
      buffer.writeln('  <dependencies>');
      for (final dep in dependencies) {
        final parts = dep.split(':');
        buffer.writeln('    <dependency>');
        buffer.writeln('      <groupId>${parts[0]}</groupId>');
        buffer.writeln('      <artifactId>${parts[1]}</artifactId>');
        if (parts.length > 2) {
          buffer.writeln('      <version>${parts[2]}</version>');
        }
        if (parts.length > 3) {
          buffer.writeln('      <scope>${parts[3]}</scope>');
        }
        buffer.writeln('    </dependency>');
      }
      buffer.writeln('  </dependencies>');
    }

    buffer.writeln('</project>');

    addPom(groupId, artifactId, version, buffer.toString());
  }

  /// Creates a POM that relocates to a new artifact.
  void addRelocatedPom(
    String groupId,
    String artifactId,
    String version, {
    String? newGroupId,
    String? newArtifactId,
    String? newVersion,
    String? message,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<project>');
    buffer.writeln('  <modelVersion>4.0.0</modelVersion>');
    buffer.writeln('  <groupId>$groupId</groupId>');
    buffer.writeln('  <artifactId>$artifactId</artifactId>');
    buffer.writeln('  <version>$version</version>');
    buffer.writeln('  <distributionManagement>');
    buffer.writeln('    <relocation>');
    if (newGroupId != null) {
      buffer.writeln('      <groupId>$newGroupId</groupId>');
    }
    if (newArtifactId != null) {
      buffer.writeln('      <artifactId>$newArtifactId</artifactId>');
    }
    if (newVersion != null) {
      buffer.writeln('      <version>$newVersion</version>');
    }
    if (message != null) {
      buffer.writeln('      <message>$message</message>');
    }
    buffer.writeln('    </relocation>');
    buffer.writeln('  </distributionManagement>');
    buffer.writeln('</project>');

    addPom(groupId, artifactId, version, buffer.toString());
  }

  @override
  Future<FetchResult?> fetchPom(ArtifactCoordinate coord) async {
    final key = '${coord.groupId}:${coord.artifactId}:${coord.version}';
    final pom = poms[key];
    if (pom == null) return null;
    return FetchResult(content: Uint8List.fromList(pom.codeUnits));
  }

  @override
  Future<FetchResult?> fetchArtifact(
    ArtifactCoordinate coord, {
    String? extension,
  }) async {
    // For tests, just return empty content if POM exists
    final key = '${coord.groupId}:${coord.artifactId}:${coord.version}';
    if (poms.containsKey(key)) {
      return FetchResult(content: Uint8List(0));
    }
    return null;
  }

  @override
  Future<List<MavenVersion>> listVersions(
    String groupId,
    String artifactId,
  ) async {
    final key = '$groupId:$artifactId';
    final versionList = versions[key] ?? [];
    return versionList.map((v) => MavenVersion.parse(v)).toList()..sort();
  }

  @override
  Future<FetchResult?> fetchRaw(String path) async {
    return null;
  }

  @override
  Future<void> close() async {}
}
