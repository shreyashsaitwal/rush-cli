import 'dart:io';
import 'dart:typed_data';

import 'package:maven_resolver/maven_resolver.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('LocalRepository', () {
    late Directory tempDir;
    late LocalRepository repo;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('maven_resolver_test_');
      repo = LocalRepository(repositoryPath: tempDir.path);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    group('fetchPom', () {
      test('returns null for non-existent POM', () async {
        const coord = ArtifactCoordinate(
          groupId: 'org.example',
          artifactId: 'my-lib',
          version: '1.0.0',
        );

        final result = await repo.fetchPom(coord);
        expect(result, isNull);
      });

      test('fetches existing POM', () async {
        const coord = ArtifactCoordinate(
          groupId: 'org.example',
          artifactId: 'my-lib',
          version: '1.0.0',
        );

        // Create the POM file
        final pomDir = Directory(
          p.join(
            tempDir.path,
            'org',
            'example',
            'my-lib',
            '1.0.0',
          ),
        );
        await pomDir.create(recursive: true);
        final pomFile = File(p.join(pomDir.path, 'my-lib-1.0.0.pom'));
        await pomFile.writeAsString('<project></project>');

        final result = await repo.fetchPom(coord);
        expect(result, isNotNull);
        expect(result!.fromCache, isTrue);
        expect(String.fromCharCodes(result.content), '<project></project>');
      });

      test('returns null for empty POM file', () async {
        const coord = ArtifactCoordinate(
          groupId: 'org.example',
          artifactId: 'my-lib',
          version: '1.0.0',
        );

        // Create an empty POM file
        final pomDir = Directory(
          p.join(
            tempDir.path,
            'org',
            'example',
            'my-lib',
            '1.0.0',
          ),
        );
        await pomDir.create(recursive: true);
        final pomFile = File(p.join(pomDir.path, 'my-lib-1.0.0.pom'));
        await pomFile.writeAsString('');

        final result = await repo.fetchPom(coord);
        expect(result, isNull);
      });
    });

    group('fetchArtifact', () {
      test('returns null for non-existent artifact', () async {
        const coord = ArtifactCoordinate(
          groupId: 'org.example',
          artifactId: 'my-lib',
          version: '1.0.0',
        );

        final result = await repo.fetchArtifact(coord);
        expect(result, isNull);
      });

      test('fetches existing jar artifact', () async {
        const coord = ArtifactCoordinate(
          groupId: 'org.example',
          artifactId: 'my-lib',
          version: '1.0.0',
        );

        // Create the jar file
        final artifactDir = Directory(
          p.join(
            tempDir.path,
            'org',
            'example',
            'my-lib',
            '1.0.0',
          ),
        );
        await artifactDir.create(recursive: true);
        final jarFile = File(p.join(artifactDir.path, 'my-lib-1.0.0.jar'));
        await jarFile.writeAsBytes([0x50, 0x4B, 0x03, 0x04]); // ZIP header

        final result = await repo.fetchArtifact(coord);
        expect(result, isNotNull);
        expect(result!.content, [0x50, 0x4B, 0x03, 0x04]);
      });

      test('fetches artifact with custom extension', () async {
        const coord = ArtifactCoordinate(
          groupId: 'org.example',
          artifactId: 'my-lib',
          version: '1.0.0',
        );

        final artifactDir = Directory(
          p.join(
            tempDir.path,
            'org',
            'example',
            'my-lib',
            '1.0.0',
          ),
        );
        await artifactDir.create(recursive: true);
        final aarFile = File(p.join(artifactDir.path, 'my-lib-1.0.0.aar'));
        await aarFile.writeAsString('aar content');

        final result = await repo.fetchArtifact(coord, extension: 'aar');
        expect(result, isNotNull);
        expect(String.fromCharCodes(result!.content), 'aar content');
      });
    });

    group('listVersions', () {
      test('returns empty list for non-existent artifact', () async {
        final versions = await repo.listVersions('org.example', 'my-lib');
        expect(versions, isEmpty);
      });

      test('lists versions from metadata file', () async {
        final artifactDir = Directory(
          p.join(
            tempDir.path,
            'org',
            'example',
            'my-lib',
          ),
        );
        await artifactDir.create(recursive: true);

        // Create maven-metadata.xml
        final metadataFile =
            File(p.join(artifactDir.path, 'maven-metadata.xml'));
        await metadataFile.writeAsString('''
<metadata>
  <groupId>org.example</groupId>
  <artifactId>my-lib</artifactId>
  <versioning>
    <versions>
      <version>1.0.0</version>
      <version>1.5.0</version>
      <version>2.0.0</version>
    </versions>
  </versioning>
</metadata>
''');

        final versions = await repo.listVersions('org.example', 'my-lib');
        expect(versions.length, 3);
        expect(versions[0].toString(), '1.0.0');
        expect(versions[1].toString(), '1.5.0');
        expect(versions[2].toString(), '2.0.0');
      });

      test('lists versions from directory scan fallback', () async {
        final artifactDir = Directory(
          p.join(
            tempDir.path,
            'org',
            'example',
            'my-lib',
          ),
        );
        await artifactDir.create(recursive: true);

        // Create version directories with POM files
        for (final version in ['1.0.0', '2.0.0', '1.5.0']) {
          final versionDir = Directory(p.join(artifactDir.path, version));
          await versionDir.create();
          final pomFile = File(p.join(versionDir.path, 'my-lib-$version.pom'));
          await pomFile.writeAsString('<project></project>');
        }

        final versions = await repo.listVersions('org.example', 'my-lib');
        expect(versions.length, 3);
        // Should be sorted
        expect(versions[0].toString(), '1.0.0');
        expect(versions[1].toString(), '1.5.0');
        expect(versions[2].toString(), '2.0.0');
      });
    });

    group('save', () {
      test('saves content to correct path', () async {
        final content = Uint8List.fromList('test content'.codeUnits);
        const path = 'org/example/my-lib/1.0.0/my-lib-1.0.0.jar';

        final file = await repo.save(path, content);

        expect(await file.exists(), isTrue);
        expect(await file.readAsString(), 'test content');
        expect(file.path, p.join(tempDir.path, path));
      });

      test('creates parent directories', () async {
        final content = Uint8List.fromList('test'.codeUnits);
        const path = 'deep/nested/path/file.txt';

        await repo.save(path, content);

        expect(await repo.exists(path), isTrue);
      });
    });

    group('exists', () {
      test('returns false for non-existent file', () async {
        expect(await repo.exists('nonexistent'), isFalse);
      });

      test('returns true for existing file', () async {
        final file = File(p.join(tempDir.path, 'test.txt'));
        await file.writeAsString('test');

        expect(await repo.exists('test.txt'), isTrue);
      });
    });

    group('fullPath', () {
      test('returns absolute path', () {
        final full = repo.fullPath('org/example/file.jar');
        expect(full, p.join(tempDir.path, 'org/example/file.jar'));
      });
    });
  });

  group('LocalRepository.defaultLocation', () {
    test('creates repository with default path', () {
      final repo = LocalRepository.defaultLocation();
      expect(repo.repositoryPath, contains('.m2'));
    });
  });
}
