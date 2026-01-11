import 'dart:convert';
import 'dart:typed_data';

import 'package:maven_resolver/maven_resolver.dart';
import 'package:test/test.dart';

void main() {
  group('MavenMetadata', () {
    group('parse - version listing metadata', () {
      test('parses basic metadata', () {
        const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<metadata>
  <groupId>org.example</groupId>
  <artifactId>my-lib</artifactId>
  <versioning>
    <latest>2.0.0</latest>
    <release>2.0.0</release>
    <versions>
      <version>1.0.0</version>
      <version>1.5.0</version>
      <version>2.0.0</version>
    </versions>
    <lastUpdated>20231128143052</lastUpdated>
  </versioning>
</metadata>
''';

        final metadata = MavenMetadata.parse(
          Uint8List.fromList(utf8.encode(xml)),
        );

        expect(metadata.groupId, 'org.example');
        expect(metadata.artifactId, 'my-lib');
        expect(metadata.versioning, isNotNull);
        expect(metadata.versioning!.latest, '2.0.0');
        expect(metadata.versioning!.release, '2.0.0');
        expect(metadata.versioning!.versions, ['1.0.0', '1.5.0', '2.0.0']);
        expect(metadata.versioning!.lastUpdated, '20231128143052');
      });

      test('returns sorted versions via versions getter', () {
        const xml = '''
<metadata>
  <groupId>org.example</groupId>
  <artifactId>my-lib</artifactId>
  <versioning>
    <versions>
      <version>2.0.0</version>
      <version>1.0.0</version>
      <version>1.5.0</version>
    </versions>
  </versioning>
</metadata>
''';

        final metadata = MavenMetadata.parse(
          Uint8List.fromList(utf8.encode(xml)),
        );

        final versions = metadata.versions;
        expect(versions.length, 3);
        expect(versions[0].toString(), '1.0.0');
        expect(versions[1].toString(), '1.5.0');
        expect(versions[2].toString(), '2.0.0');
      });

      test('parses latest and release as MavenVersion', () {
        const xml = '''
<metadata>
  <groupId>org.example</groupId>
  <artifactId>my-lib</artifactId>
  <versioning>
    <latest>2.0.0-SNAPSHOT</latest>
    <release>1.5.0</release>
    <versions>
      <version>1.5.0</version>
    </versions>
  </versioning>
</metadata>
''';

        final metadata = MavenMetadata.parse(
          Uint8List.fromList(utf8.encode(xml)),
        );

        expect(metadata.latest, isNotNull);
        expect(metadata.latest!.toString(), '2.0.0-SNAPSHOT');
        expect(metadata.release, isNotNull);
        expect(metadata.release!.toString(), '1.5.0');
      });
    });

    group('parse - SNAPSHOT metadata', () {
      test('parses SNAPSHOT versioning', () {
        const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<metadata>
  <groupId>org.example</groupId>
  <artifactId>my-lib</artifactId>
  <version>1.0-SNAPSHOT</version>
  <versioning>
    <snapshot>
      <timestamp>20231128.143052</timestamp>
      <buildNumber>42</buildNumber>
    </snapshot>
    <lastUpdated>20231128143052</lastUpdated>
    <snapshotVersions>
      <snapshotVersion>
        <extension>jar</extension>
        <value>1.0-20231128.143052-42</value>
        <updated>20231128143052</updated>
      </snapshotVersion>
      <snapshotVersion>
        <extension>pom</extension>
        <value>1.0-20231128.143052-42</value>
        <updated>20231128143052</updated>
      </snapshotVersion>
      <snapshotVersion>
        <classifier>sources</classifier>
        <extension>jar</extension>
        <value>1.0-20231128.143052-42</value>
        <updated>20231128143052</updated>
      </snapshotVersion>
    </snapshotVersions>
  </versioning>
</metadata>
''';

        final metadata = MavenMetadata.parse(
          Uint8List.fromList(utf8.encode(xml)),
        );

        expect(metadata.version, '1.0-SNAPSHOT');
        expect(metadata.versioning, isNotNull);

        final snapshot = metadata.versioning!.snapshot;
        expect(snapshot, isNotNull);
        expect(snapshot!.timestamp, '20231128.143052');
        expect(snapshot.buildNumber, 42);
        expect(snapshot.localCopy, isFalse);

        final snapshotVersions = metadata.versioning!.snapshotVersions;
        expect(snapshotVersions.length, 3);

        // Check jar entry
        final jarEntry = snapshotVersions
            .firstWhere((sv) => sv.extension == 'jar' && sv.classifier == null);
        expect(jarEntry.value, '1.0-20231128.143052-42');
        expect(jarEntry.updated, '20231128143052');

        // Check sources entry
        final sourcesEntry =
            snapshotVersions.firstWhere((sv) => sv.classifier == 'sources');
        expect(sourcesEntry.extension, 'jar');
        expect(sourcesEntry.value, '1.0-20231128.143052-42');
      });

      test('parses local snapshot', () {
        const xml = '''
<metadata>
  <groupId>org.example</groupId>
  <artifactId>my-lib</artifactId>
  <version>1.0-SNAPSHOT</version>
  <versioning>
    <snapshot>
      <localCopy>true</localCopy>
    </snapshot>
  </versioning>
</metadata>
''';

        final metadata = MavenMetadata.parse(
          Uint8List.fromList(utf8.encode(xml)),
        );

        final snapshot = metadata.versioning!.snapshot;
        expect(snapshot, isNotNull);
        expect(snapshot!.localCopy, isTrue);
      });
    });

    test('throws MetadataParseException on invalid XML', () {
      const invalidXml = 'not xml at all';

      expect(
        () => MavenMetadata.parse(Uint8List.fromList(utf8.encode(invalidXml))),
        throwsA(isA<MetadataParseException>()),
      );
    });

    test('throws MetadataParseException on wrong root element', () {
      const wrongRoot = '<project></project>';

      expect(
        () => MavenMetadata.parse(Uint8List.fromList(utf8.encode(wrongRoot))),
        throwsA(isA<MetadataParseException>()),
      );
    });
  });

  group('SnapshotResolver', () {
    late SnapshotResolver resolver;

    setUp(() {
      resolver = const SnapshotResolver();
    });

    test('resolves filename from snapshotVersions', () {
      const xml = '''
<metadata>
  <groupId>org.example</groupId>
  <artifactId>my-lib</artifactId>
  <version>1.0-SNAPSHOT</version>
  <versioning>
    <snapshot>
      <timestamp>20231128.143052</timestamp>
      <buildNumber>42</buildNumber>
    </snapshot>
    <snapshotVersions>
      <snapshotVersion>
        <extension>jar</extension>
        <value>1.0-20231128.143052-42</value>
      </snapshotVersion>
    </snapshotVersions>
  </versioning>
</metadata>
''';

      final metadata = MavenMetadata.parse(
        Uint8List.fromList(utf8.encode(xml)),
      );
      const coord = ArtifactCoordinate(
        groupId: 'org.example',
        artifactId: 'my-lib',
        version: '1.0-SNAPSHOT',
      );

      final filename = resolver.resolveFilename(
        coord: coord,
        metadata: metadata,
      );

      expect(filename, 'my-lib-1.0-20231128.143052-42.jar');
    });

    test('resolves filename with classifier', () {
      const xml = '''
<metadata>
  <groupId>org.example</groupId>
  <artifactId>my-lib</artifactId>
  <version>1.0-SNAPSHOT</version>
  <versioning>
    <snapshotVersions>
      <snapshotVersion>
        <classifier>sources</classifier>
        <extension>jar</extension>
        <value>1.0-20231128.143052-42</value>
      </snapshotVersion>
    </snapshotVersions>
  </versioning>
</metadata>
''';

      final metadata = MavenMetadata.parse(
        Uint8List.fromList(utf8.encode(xml)),
      );
      const coord = ArtifactCoordinate(
        groupId: 'org.example',
        artifactId: 'my-lib',
        version: '1.0-SNAPSHOT',
        classifier: 'sources',
      );

      final filename = resolver.resolveFilename(
        coord: coord,
        metadata: metadata,
      );

      expect(filename, 'my-lib-1.0-20231128.143052-42-sources.jar');
    });

    test('falls back to timestamp/buildNumber when no matching entry', () {
      const xml = '''
<metadata>
  <groupId>org.example</groupId>
  <artifactId>my-lib</artifactId>
  <version>1.0-SNAPSHOT</version>
  <versioning>
    <snapshot>
      <timestamp>20231128.143052</timestamp>
      <buildNumber>42</buildNumber>
    </snapshot>
    <snapshotVersions>
      <snapshotVersion>
        <extension>pom</extension>
        <value>1.0-20231128.143052-42</value>
      </snapshotVersion>
    </snapshotVersions>
  </versioning>
</metadata>
''';

      final metadata = MavenMetadata.parse(
        Uint8List.fromList(utf8.encode(xml)),
      );
      const coord = ArtifactCoordinate(
        groupId: 'org.example',
        artifactId: 'my-lib',
        version: '1.0-SNAPSHOT',
      );

      final filename = resolver.resolveFilename(
        coord: coord,
        metadata: metadata,
        extension: 'jar',
      );

      expect(filename, 'my-lib-1.0-20231128.143052-42.jar');
    });

    test('returns null for non-SNAPSHOT version', () {
      const xml = '''
<metadata>
  <groupId>org.example</groupId>
  <artifactId>my-lib</artifactId>
</metadata>
''';

      final metadata = MavenMetadata.parse(
        Uint8List.fromList(utf8.encode(xml)),
      );
      const coord = ArtifactCoordinate(
        groupId: 'org.example',
        artifactId: 'my-lib',
        version: '1.0.0', // Not a SNAPSHOT
      );

      final filename = resolver.resolveFilename(
        coord: coord,
        metadata: metadata,
      );

      expect(filename, isNull);
    });
  });
}
