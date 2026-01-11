import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maven_resolver/maven_resolver.dart';
import 'package:test/test.dart';

void main() {
  group('RemoteRepository', () {
    late MockClient mockClient;
    late RemoteRepository repo;

    group('fetchRaw', () {
      test('returns content for 200 response', () async {
        mockClient = MockClient((request) async {
          expect(request.url.path, '/maven2/org/example/file.txt');
          return http.Response('file content', 200);
        });

        repo = RemoteRepository(
          url: 'https://repo1.maven.org/maven2/',
          client: mockClient,
          config: const RemoteRepositoryConfig(
            checksumPolicy: ChecksumPolicy.ignore,
          ),
        );

        final result = await repo.fetchRaw('org/example/file.txt');

        expect(result, isNotNull);
        expect(String.fromCharCodes(result!.content), 'file content');
        expect(result.fromCache, isFalse);
      });

      test('returns null for 404 response', () async {
        mockClient = MockClient((request) async {
          return http.Response('Not found', 404);
        });

        repo = RemoteRepository(
          url: 'https://repo1.maven.org/maven2/',
          client: mockClient,
          config: const RemoteRepositoryConfig(
            checksumPolicy: ChecksumPolicy.ignore,
          ),
        );

        final result = await repo.fetchRaw('nonexistent');
        expect(result, isNull);
      });

      test('throws on network error after retries', () async {
        mockClient = MockClient((request) async {
          throw const SocketException('Connection failed');
        });

        repo = RemoteRepository(
          url: 'https://repo1.maven.org/maven2/',
          client: mockClient,
          config: const RemoteRepositoryConfig(
            maxRetries: 3,
            retryDelay: Duration(milliseconds: 10),
            checksumPolicy: ChecksumPolicy.ignore,
          ),
        );

        expect(
          () => repo.fetchRaw('org/example/file.txt'),
          throwsA(isA<RepositoryRetryExhaustedException>()),
        );
      });
    });

    group('fetchPom', () {
      test('fetches POM at correct path', () async {
        mockClient = MockClient((request) async {
          if (request.url.path.endsWith('.pom')) {
            return http.Response('<project></project>', 200);
          }
          return http.Response('Not found', 404);
        });

        repo = RemoteRepository(
          url: 'https://repo1.maven.org/maven2/',
          client: mockClient,
          config: const RemoteRepositoryConfig(
            checksumPolicy: ChecksumPolicy.ignore,
          ),
        );

        const coord = ArtifactCoordinate(
          groupId: 'org.example',
          artifactId: 'my-lib',
          version: '1.0.0',
        );

        final result = await repo.fetchPom(coord);
        expect(result, isNotNull);
        expect(String.fromCharCodes(result!.content), '<project></project>');
      });
    });

    group('fetchArtifact', () {
      test('fetches artifact at correct path', () async {
        mockClient = MockClient((request) async {
          if (request.url.path.endsWith('.jar')) {
            return http.Response.bytes([0x50, 0x4B, 0x03, 0x04], 200);
          }
          return http.Response('Not found', 404);
        });

        repo = RemoteRepository(
          url: 'https://repo1.maven.org/maven2/',
          client: mockClient,
          config: const RemoteRepositoryConfig(
            checksumPolicy: ChecksumPolicy.ignore,
          ),
        );

        const coord = ArtifactCoordinate(
          groupId: 'org.example',
          artifactId: 'my-lib',
          version: '1.0.0',
        );

        final result = await repo.fetchArtifact(coord);
        expect(result, isNotNull);
        expect(result!.content, [0x50, 0x4B, 0x03, 0x04]);
      });
    });

    group('listVersions', () {
      test('parses versions from metadata', () async {
        mockClient = MockClient((request) async {
          if (request.url.path.contains('maven-metadata.xml')) {
            return http.Response(
              '''
<metadata>
  <groupId>org.example</groupId>
  <artifactId>my-lib</artifactId>
  <versioning>
    <versions>
      <version>1.0.0</version>
      <version>2.0.0</version>
    </versions>
  </versioning>
</metadata>
''',
              200,
            );
          }
          return http.Response('Not found', 404);
        });

        repo = RemoteRepository(
          url: 'https://repo1.maven.org/maven2/',
          client: mockClient,
          config: const RemoteRepositoryConfig(
            checksumPolicy: ChecksumPolicy.ignore,
          ),
        );

        final versions = await repo.listVersions('org.example', 'my-lib');
        expect(versions.length, 2);
        expect(versions[0].toString(), '1.0.0');
        expect(versions[1].toString(), '2.0.0');
      });

      test('returns empty list when metadata not found', () async {
        mockClient = MockClient((request) async {
          return http.Response('Not found', 404);
        });

        repo = RemoteRepository(
          url: 'https://repo1.maven.org/maven2/',
          client: mockClient,
          config: const RemoteRepositoryConfig(
            checksumPolicy: ChecksumPolicy.ignore,
          ),
        );

        final versions = await repo.listVersions('nonexistent', 'artifact');
        expect(versions, isEmpty);
      });
    });

    group('SNAPSHOT resolution', () {
      test('resolves SNAPSHOT to timestamped version', () async {
        mockClient = MockClient((request) async {
          final path = request.url.path;

          if (path.contains('maven-metadata.xml')) {
            return http.Response(
              '''
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
''',
              200,
            );
          }

          if (path.contains('1.0-20231128.143052-42.jar')) {
            return http.Response.bytes([0x50, 0x4B, 0x03, 0x04], 200);
          }

          return http.Response('Not found', 404);
        });

        repo = RemoteRepository(
          url: 'https://repo1.maven.org/maven2/',
          client: mockClient,
          config: const RemoteRepositoryConfig(
            checksumPolicy: ChecksumPolicy.ignore,
          ),
        );

        const coord = ArtifactCoordinate(
          groupId: 'org.example',
          artifactId: 'my-lib',
          version: '1.0-SNAPSHOT',
        );

        final result = await repo.fetchArtifact(coord);
        expect(result, isNotNull);
      });
    });

    group('checksum verification', () {
      test('verifies SHA1 checksum', () async {
        const content = 'hello world';
        const sha1 = '2aae6c35c94fcfb415dbe95f408b9ce91ee846ed';

        mockClient = MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('.jar.sha1')) {
            return http.Response(sha1, 200);
          }
          if (path.endsWith('.jar')) {
            return http.Response(content, 200);
          }
          return http.Response('Not found', 404);
        });

        repo = RemoteRepository(
          url: 'https://repo1.maven.org/maven2/',
          client: mockClient,
          config: const RemoteRepositoryConfig(
            checksumPolicy: ChecksumPolicy.fail,
          ),
        );

        const coord = ArtifactCoordinate(
          groupId: 'org.example',
          artifactId: 'my-lib',
          version: '1.0.0',
        );

        final result = await repo.fetchArtifact(coord);
        expect(result, isNotNull);
        expect(String.fromCharCodes(result!.content), content);
      });

      test('throws on checksum mismatch with fail policy', () async {
        mockClient = MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('.jar.sha1')) {
            return http.Response('wrong_checksum', 200);
          }
          if (path.endsWith('.jar')) {
            return http.Response('hello world', 200);
          }
          return http.Response('Not found', 404);
        });

        repo = RemoteRepository(
          url: 'https://repo1.maven.org/maven2/',
          client: mockClient,
          config: const RemoteRepositoryConfig(
            checksumPolicy: ChecksumPolicy.fail,
          ),
        );

        const coord = ArtifactCoordinate(
          groupId: 'org.example',
          artifactId: 'my-lib',
          version: '1.0.0',
        );

        expect(
          () => repo.fetchArtifact(coord),
          throwsA(isA<ChecksumVerificationException>()),
        );
      });
    });

    group('caching', () {
      test('uses local cache when available', () async {
        final tempDir =
            await Directory.systemTemp.createTemp('maven_resolver_cache_');
        try {
          final localRepo = LocalRepository(repositoryPath: tempDir.path);

          // Pre-populate cache
          await localRepo.save(
            'org/example/my-lib/1.0.0/my-lib-1.0.0.jar',
            Uint8List.fromList('cached content'.codeUnits),
          );

          mockClient = MockClient((request) async {
            fail('Should not make HTTP request when cached');
          });

          repo = RemoteRepository(
            url: 'https://repo1.maven.org/maven2/',
            client: mockClient,
            localCache: localRepo,
            config: const RemoteRepositoryConfig(
              checksumPolicy: ChecksumPolicy.ignore,
            ),
          );

          const coord = ArtifactCoordinate(
            groupId: 'org.example',
            artifactId: 'my-lib',
            version: '1.0.0',
          );

          final result = await repo.fetchArtifact(coord);
          expect(result, isNotNull);
          expect(String.fromCharCodes(result!.content), 'cached content');
          expect(result.fromCache, isTrue);
        } finally {
          await tempDir.delete(recursive: true);
        }
      });
    });
  });

  group('CompositeRepository', () {
    test('searches repositories in order', () async {
      var repo1Called = false;
      var repo2Called = false;

      final mockClient1 = MockClient((request) async {
        repo1Called = true;
        return http.Response('Not found', 404);
      });

      final mockClient2 = MockClient((request) async {
        repo2Called = true;
        return http.Response('from repo2', 200);
      });

      final repo1 = RemoteRepository(
        url: 'https://repo1.example.com/',
        id: 'repo1',
        client: mockClient1,
        config: const RemoteRepositoryConfig(
          checksumPolicy: ChecksumPolicy.ignore,
        ),
      );

      final repo2 = RemoteRepository(
        url: 'https://repo2.example.com/',
        id: 'repo2',
        client: mockClient2,
        config: const RemoteRepositoryConfig(
          checksumPolicy: ChecksumPolicy.ignore,
        ),
      );

      final composite = CompositeRepository([repo1, repo2]);

      final result = await composite.fetchRaw('test.txt');

      expect(repo1Called, isTrue);
      expect(repo2Called, isTrue);
      expect(result, isNotNull);
      expect(String.fromCharCodes(result!.content), 'from repo2');
    });

    test('stops on first successful result', () async {
      var repo2Called = false;

      final mockClient1 = MockClient((request) async {
        return http.Response('from repo1', 200);
      });

      final mockClient2 = MockClient((request) async {
        repo2Called = true;
        return http.Response('from repo2', 200);
      });

      final repo1 = RemoteRepository(
        url: 'https://repo1.example.com/',
        client: mockClient1,
        config: const RemoteRepositoryConfig(
          checksumPolicy: ChecksumPolicy.ignore,
        ),
      );

      final repo2 = RemoteRepository(
        url: 'https://repo2.example.com/',
        client: mockClient2,
        config: const RemoteRepositoryConfig(
          checksumPolicy: ChecksumPolicy.ignore,
        ),
      );

      final composite = CompositeRepository([repo1, repo2]);

      final result = await composite.fetchRaw('test.txt');

      expect(repo2Called, isFalse);
      expect(String.fromCharCodes(result!.content), 'from repo1');
    });

    test('merges versions from all repositories', () async {
      final mockClient1 = MockClient((request) async {
        return http.Response(
          '''
<metadata>
  <groupId>org.example</groupId>
  <artifactId>my-lib</artifactId>
  <versioning>
    <versions>
      <version>1.0.0</version>
    </versions>
  </versioning>
</metadata>
''',
          200,
        );
      });

      final mockClient2 = MockClient((request) async {
        return http.Response(
          '''
<metadata>
  <groupId>org.example</groupId>
  <artifactId>my-lib</artifactId>
  <versioning>
    <versions>
      <version>2.0.0</version>
    </versions>
  </versioning>
</metadata>
''',
          200,
        );
      });

      final repo1 = RemoteRepository(
        url: 'https://repo1.example.com/',
        client: mockClient1,
        config: const RemoteRepositoryConfig(
          checksumPolicy: ChecksumPolicy.ignore,
        ),
      );

      final repo2 = RemoteRepository(
        url: 'https://repo2.example.com/',
        client: mockClient2,
        config: const RemoteRepositoryConfig(
          checksumPolicy: ChecksumPolicy.ignore,
        ),
      );

      final composite = CompositeRepository([repo1, repo2]);

      final versions = await composite.listVersions('org.example', 'my-lib');

      expect(versions.length, 2);
      expect(versions[0].toString(), '1.0.0');
      expect(versions[1].toString(), '2.0.0');
    });
  });

  group('MavenRepositories', () {
    test('central URL is correct', () {
      expect(MavenRepositories.central, 'https://repo1.maven.org/maven2/');
    });

    test('google URL is correct', () {
      expect(MavenRepositories.google, 'https://maven.google.com/');
    });
  });
}
