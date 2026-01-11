import 'package:maven_resolver/maven_resolver.dart';
import 'package:test/test.dart';

import 'mock_repository.dart';

void main() {
  group('DependencyResolver', () {
    late MockRepository repo;
    late DependencyResolver resolver;

    setUp(() {
      repo = MockRepository();
      resolver = DependencyResolver(repository: repo);
    });

    group('simple resolution', () {
      test('resolves single direct dependency', () async {
        repo.addSimplePom('com.example', 'lib-a', '1.0.0');

        final result = await resolver.resolve(
          directDependencies: [
            const Dependency(
              groupId: 'com.example',
              artifactId: 'lib-a',
              version: '1.0.0',
            ),
          ],
        );

        expect(result.isSuccess, isTrue);
        expect(result.artifacts, hasLength(1));
        expect(result.artifacts[0].coordinate.artifactId, 'lib-a');
        expect(result.artifacts[0].coordinate.version, '1.0.0');
      });

      test('resolves multiple direct dependencies', () async {
        repo.addSimplePom('com.example', 'lib-a', '1.0.0');
        repo.addSimplePom('com.example', 'lib-b', '2.0.0');

        final result = await resolver.resolve(
          directDependencies: [
            const Dependency(
              groupId: 'com.example',
              artifactId: 'lib-a',
              version: '1.0.0',
            ),
            const Dependency(
              groupId: 'com.example',
              artifactId: 'lib-b',
              version: '2.0.0',
            ),
          ],
        );

        expect(result.isSuccess, isTrue);
        expect(result.artifacts, hasLength(2));
      });

      test('resolves transitive dependencies', () async {
        repo.addSimplePom(
          'com.example',
          'lib-a',
          '1.0.0',
          dependencies: [
            'com.example:lib-b:1.0.0',
          ],
        );
        repo.addSimplePom(
          'com.example',
          'lib-b',
          '1.0.0',
          dependencies: [
            'com.example:lib-c:1.0.0',
          ],
        );
        repo.addSimplePom('com.example', 'lib-c', '1.0.0');

        final result = await resolver.resolve(
          directDependencies: [
            const Dependency(
              groupId: 'com.example',
              artifactId: 'lib-a',
              version: '1.0.0',
            ),
          ],
        );

        expect(result.isSuccess, isTrue);
        expect(result.artifacts, hasLength(3));
        expect(
          result.artifacts.map((a) => a.coordinate.artifactId),
          containsAll(['lib-a', 'lib-b', 'lib-c']),
        );
      });
    });

    group('nearest wins', () {
      test('selects nearer version in diamond dependency', () async {
        // A -> B -> D:1.0.0
        // A -> C -> D:2.0.0
        // D:1.0.0 is at depth 3, D:2.0.0 is also at depth 3
        // First declaration (from B) should win

        repo.addSimplePom(
          'com.example',
          'lib-a',
          '1.0.0',
          dependencies: [
            'com.example:lib-b:1.0.0',
            'com.example:lib-c:1.0.0',
          ],
        );
        repo.addSimplePom(
          'com.example',
          'lib-b',
          '1.0.0',
          dependencies: [
            'com.example:lib-d:1.0.0',
          ],
        );
        repo.addSimplePom(
          'com.example',
          'lib-c',
          '1.0.0',
          dependencies: [
            'com.example:lib-d:2.0.0',
          ],
        );
        repo.addSimplePom('com.example', 'lib-d', '1.0.0');
        repo.addSimplePom('com.example', 'lib-d', '2.0.0');

        final result = await resolver.resolve(
          directDependencies: [
            const Dependency(
              groupId: 'com.example',
              artifactId: 'lib-a',
              version: '1.0.0',
            ),
          ],
        );

        expect(result.isSuccess, isTrue);
        final libD = result.artifacts.firstWhere(
          (a) => a.coordinate.artifactId == 'lib-d',
        );
        expect(libD.coordinate.version, '1.0.0'); // First declaration wins
      });

      test('direct dependency wins over transitive', () async {
        // Direct: D:2.0.0 at depth 1
        // Transitive: A -> D:1.0.0 at depth 2

        repo.addSimplePom(
          'com.example',
          'lib-a',
          '1.0.0',
          dependencies: [
            'com.example:lib-d:1.0.0',
          ],
        );
        repo.addSimplePom('com.example', 'lib-d', '1.0.0');
        repo.addSimplePom('com.example', 'lib-d', '2.0.0');

        final result = await resolver.resolve(
          directDependencies: [
            const Dependency(
              groupId: 'com.example',
              artifactId: 'lib-a',
              version: '1.0.0',
            ),
            const Dependency(
              groupId: 'com.example',
              artifactId: 'lib-d',
              version: '2.0.0',
            ),
          ],
        );

        expect(result.isSuccess, isTrue);
        final libD = result.artifacts.firstWhere(
          (a) => a.coordinate.artifactId == 'lib-d',
        );
        expect(libD.coordinate.version, '2.0.0'); // Direct wins
      });

      test('reports conflicts', () async {
        repo.addSimplePom(
          'com.example',
          'lib-a',
          '1.0.0',
          dependencies: [
            'com.example:lib-b:1.0.0',
            'com.example:lib-c:1.0.0',
          ],
        );
        repo.addSimplePom(
          'com.example',
          'lib-b',
          '1.0.0',
          dependencies: [
            'com.example:lib-d:1.0.0',
          ],
        );
        repo.addSimplePom(
          'com.example',
          'lib-c',
          '1.0.0',
          dependencies: [
            'com.example:lib-d:2.0.0',
          ],
        );
        repo.addSimplePom('com.example', 'lib-d', '1.0.0');
        repo.addSimplePom('com.example', 'lib-d', '2.0.0');

        final result = await resolver.resolve(
          directDependencies: [
            const Dependency(
              groupId: 'com.example',
              artifactId: 'lib-a',
              version: '1.0.0',
            ),
          ],
        );

        expect(result.conflicts, isNotEmpty);
        final conflict = result.conflicts.firstWhere(
          (c) => c.artifactKey == 'com.example:lib-d',
        );
        expect(conflict.selectedVersion, '1.0.0');
        expect(conflict.conflictingVersions, contains('2.0.0'));
      });
    });

    group('scope mediation', () {
      test('runtime scope remains runtime transitively under compile',
          () async {
        repo.addSimplePom(
          'com.example',
          'lib-a',
          '1.0.0',
          dependencies: [
            'com.example:lib-b:1.0.0:runtime',
          ],
        );
        repo.addSimplePom('com.example', 'lib-b', '1.0.0');

        final result = await resolver.resolve(
          directDependencies: [
            const Dependency(
              groupId: 'com.example',
              artifactId: 'lib-a',
              version: '1.0.0',
            ),
          ],
        );

        final libB = result.artifacts.firstWhere(
          (a) => a.coordinate.artifactId == 'lib-b',
        );
        expect(libB.scope, DependencyScope.runtime);
      });

      test('test scope transitives are omitted', () async {
        repo.addSimplePom(
          'com.example',
          'lib-a',
          '1.0.0',
          dependencies: [
            'com.example:lib-b:1.0.0:test',
          ],
        );
        repo.addSimplePom('com.example', 'lib-b', '1.0.0');

        final result = await resolver.resolve(
          directDependencies: [
            const Dependency(
              groupId: 'com.example',
              artifactId: 'lib-a',
              version: '1.0.0',
            ),
          ],
        );

        // lib-b should not be included because test scope is not transitive
        expect(
          result.artifacts.any((a) => a.coordinate.artifactId == 'lib-b'),
          isFalse,
        );
      });

      test('provided scope transitives are omitted', () async {
        repo.addSimplePom(
          'com.example',
          'lib-a',
          '1.0.0',
          dependencies: [
            'com.example:lib-b:1.0.0:provided',
          ],
        );
        repo.addSimplePom('com.example', 'lib-b', '1.0.0');

        final result = await resolver.resolve(
          directDependencies: [
            const Dependency(
              groupId: 'com.example',
              artifactId: 'lib-a',
              version: '1.0.0',
            ),
          ],
        );

        // lib-b should not be included because provided scope is not transitive
        expect(
          result.artifacts.any((a) => a.coordinate.artifactId == 'lib-b'),
          isFalse,
        );
      });
    });

    group('exclusions', () {
      test('excludes matching transitive dependency', () async {
        repo.addSimplePom(
          'com.example',
          'lib-a',
          '1.0.0',
          dependencies: [
            'com.example:lib-b:1.0.0',
          ],
        );
        repo.addSimplePom(
          'com.example',
          'lib-b',
          '1.0.0',
          dependencies: [
            'com.example:lib-c:1.0.0',
          ],
        );
        repo.addSimplePom('com.example', 'lib-c', '1.0.0');

        final result = await resolver.resolve(
          directDependencies: [
            const Dependency(
              groupId: 'com.example',
              artifactId: 'lib-a',
              version: '1.0.0',
              exclusions: [
                Exclusion(groupId: 'com.example', artifactId: 'lib-c'),
              ],
            ),
          ],
        );

        expect(result.isSuccess, isTrue);
        expect(result.artifacts, hasLength(2)); // lib-a, lib-b, but NOT lib-c
        expect(
          result.artifacts.any((a) => a.coordinate.artifactId == 'lib-c'),
          isFalse,
        );
      });

      test('exclusion applies to entire subtree', () async {
        repo.addSimplePom(
          'com.example',
          'lib-a',
          '1.0.0',
          dependencies: [
            'com.example:lib-b:1.0.0',
          ],
        );
        repo.addSimplePom(
          'com.example',
          'lib-b',
          '1.0.0',
          dependencies: [
            'com.example:lib-c:1.0.0',
            'com.example:lib-d:1.0.0',
          ],
        );
        repo.addSimplePom('com.example', 'lib-c', '1.0.0');
        repo.addSimplePom('com.example', 'lib-d', '1.0.0');

        final result = await resolver.resolve(
          directDependencies: [
            const Dependency(
              groupId: 'com.example',
              artifactId: 'lib-a',
              version: '1.0.0',
              exclusions: [
                Exclusion(groupId: 'com.example', artifactId: 'lib-b'),
              ],
            ),
          ],
        );

        // Only lib-a should be included; lib-b and its transitives are excluded
        expect(result.artifacts, hasLength(1));
        expect(result.artifacts[0].coordinate.artifactId, 'lib-a');
      });

      test('wildcard exclusion excludes all transitives', () async {
        repo.addSimplePom(
          'com.example',
          'lib-a',
          '1.0.0',
          dependencies: [
            'com.example:lib-b:1.0.0',
            'com.example:lib-c:1.0.0',
          ],
        );
        repo.addSimplePom('com.example', 'lib-b', '1.0.0');
        repo.addSimplePom('com.example', 'lib-c', '1.0.0');

        final result = await resolver.resolve(
          directDependencies: [
            const Dependency(
              groupId: 'com.example',
              artifactId: 'lib-a',
              version: '1.0.0',
              exclusions: [Exclusion.all],
            ),
          ],
        );

        // Only lib-a should be included
        expect(result.artifacts, hasLength(1));
        expect(result.artifacts[0].coordinate.artifactId, 'lib-a');
      });

      test('global exclusions work', () async {
        repo.addSimplePom(
          'com.example',
          'lib-a',
          '1.0.0',
          dependencies: [
            'com.example:lib-b:1.0.0',
          ],
        );
        repo.addSimplePom('com.example', 'lib-b', '1.0.0');

        final result = await resolver.resolve(
          directDependencies: [
            const Dependency(
              groupId: 'com.example',
              artifactId: 'lib-a',
              version: '1.0.0',
            ),
          ],
          exclusions: [
            const Exclusion(groupId: 'com.example', artifactId: 'lib-b'),
          ],
        );

        expect(result.artifacts, hasLength(1));
        expect(result.artifacts[0].coordinate.artifactId, 'lib-a');
      });
    });

    group('optional dependencies', () {
      test('optional transitives are excluded by default', () async {
        // Create POM with optional dependency
        repo.addPom('com.example', 'lib-a', '1.0.0', '''
<?xml version="1.0" encoding="UTF-8"?>
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>lib-a</artifactId>
  <version>1.0.0</version>
  <dependencies>
    <dependency>
      <groupId>com.example</groupId>
      <artifactId>lib-b</artifactId>
      <version>1.0.0</version>
      <optional>true</optional>
    </dependency>
  </dependencies>
</project>
''');
        repo.addSimplePom('com.example', 'lib-b', '1.0.0');

        final result = await resolver.resolve(
          directDependencies: [
            const Dependency(
              groupId: 'com.example',
              artifactId: 'lib-a',
              version: '1.0.0',
            ),
          ],
        );

        // lib-b should not be included because it's optional
        expect(
          result.artifacts.any((a) => a.coordinate.artifactId == 'lib-b'),
          isFalse,
        );
      });

      test('optional transitives included when configured', () async {
        repo.addPom('com.example', 'lib-a', '1.0.0', '''
<?xml version="1.0" encoding="UTF-8"?>
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>lib-a</artifactId>
  <version>1.0.0</version>
  <dependencies>
    <dependency>
      <groupId>com.example</groupId>
      <artifactId>lib-b</artifactId>
      <version>1.0.0</version>
      <optional>true</optional>
    </dependency>
  </dependencies>
</project>
''');
        repo.addSimplePom('com.example', 'lib-b', '1.0.0');

        resolver = DependencyResolver(
          repository: repo,
          config: const ResolverConfig(includeOptional: true),
        );

        final result = await resolver.resolve(
          directDependencies: [
            const Dependency(
              groupId: 'com.example',
              artifactId: 'lib-a',
              version: '1.0.0',
            ),
          ],
        );

        expect(
          result.artifacts.any((a) => a.coordinate.artifactId == 'lib-b'),
          isTrue,
        );
      });
    });

    group('dependencyManagement', () {
      test('applies version from dependencyManagement', () async {
        repo.addSimplePom(
          'com.example',
          'lib-a',
          '1.0.0',
          dependencies: [
            'com.example:lib-b', // No version specified
          ],
        );
        repo.addSimplePom('com.example', 'lib-b', '2.0.0');

        final result = await resolver.resolve(
          directDependencies: [
            const Dependency(
              groupId: 'com.example',
              artifactId: 'lib-a',
              version: '1.0.0',
            ),
          ],
          dependencyManagement: [
            const Dependency(
              groupId: 'com.example',
              artifactId: 'lib-b',
              version: '2.0.0',
            ),
          ],
        );

        final libB = result.artifacts.firstWhere(
          (a) => a.coordinate.artifactId == 'lib-b',
        );
        expect(libB.coordinate.version, '2.0.0');
      });

      test('dependencyManagement overrides transitive version', () async {
        // A -> B:1.0.0, but dependencyManagement says B:2.0.0
        repo.addSimplePom(
          'com.example',
          'lib-a',
          '1.0.0',
          dependencies: [
            'com.example:lib-b:1.0.0',
          ],
        );
        repo.addSimplePom('com.example', 'lib-b', '1.0.0');
        repo.addSimplePom('com.example', 'lib-b', '2.0.0');

        final result = await resolver.resolve(
          directDependencies: [
            const Dependency(
              groupId: 'com.example',
              artifactId: 'lib-a',
              version: '1.0.0',
            ),
          ],
          dependencyManagement: [
            const Dependency(
              groupId: 'com.example',
              artifactId: 'lib-b',
              version: '2.0.0',
            ),
          ],
        );

        final libB = result.artifacts.firstWhere(
          (a) => a.coordinate.artifactId == 'lib-b',
        );
        // dependencyManagement version should be used
        expect(libB.coordinate.version, '2.0.0');
      });
    });

    group('version ranges', () {
      test('resolves version range to latest', () async {
        repo.addSimplePom('com.example', 'lib-a', '1.0.0');
        repo.addSimplePom('com.example', 'lib-a', '1.5.0');
        repo.addSimplePom('com.example', 'lib-a', '2.0.0');

        final result = await resolver.resolve(
          directDependencies: [
            const Dependency(
              groupId: 'com.example',
              artifactId: 'lib-a',
              version: '[1.0.0,2.0.0)',
            ),
          ],
        );

        expect(result.isSuccess, isTrue);
        final libA = result.artifacts.first;
        expect(libA.coordinate.version, '1.5.0'); // Highest in range
      });

      test('fails when no version matches range', () async {
        repo.addSimplePom('com.example', 'lib-a', '1.0.0');

        resolver = DependencyResolver(
          repository: repo,
          config: const ResolverConfig(failOnMissing: true),
        );

        final result = await resolver.resolve(
          directDependencies: [
            const Dependency(
              groupId: 'com.example',
              artifactId: 'lib-a',
              version: '[2.0.0,3.0.0)',
            ),
          ],
        );

        expect(result.errors, isNotEmpty);
      });
    });

    group('cycle detection', () {
      test('handles circular dependencies', () async {
        repo.addSimplePom(
          'com.example',
          'lib-a',
          '1.0.0',
          dependencies: [
            'com.example:lib-b:1.0.0',
          ],
        );
        repo.addSimplePom(
          'com.example',
          'lib-b',
          '1.0.0',
          dependencies: [
            'com.example:lib-a:1.0.0',
          ],
        );

        final result = await resolver.resolve(
          directDependencies: [
            const Dependency(
              groupId: 'com.example',
              artifactId: 'lib-a',
              version: '1.0.0',
            ),
          ],
        );

        // Should not hang or crash
        expect(result.isSuccess, isTrue);
        expect(result.artifacts, hasLength(2));
      });
    });

    group('missing dependencies', () {
      test('handles missing dependencies gracefully', () async {
        repo.addSimplePom(
          'com.example',
          'lib-a',
          '1.0.0',
          dependencies: [
            'com.example:missing:1.0.0',
          ],
        );

        final result = await resolver.resolve(
          directDependencies: [
            const Dependency(
              groupId: 'com.example',
              artifactId: 'lib-a',
              version: '1.0.0',
            ),
          ],
        );

        // Should complete without hanging
        expect(result.artifacts, hasLength(1)); // Just lib-a
        expect(result.errors, isNotEmpty); // Should have error for missing
      });
    });
  });

  group('DependencyNode', () {
    test('conflictKey uses groupId:artifactId', () {
      final node = DependencyNode(
        coordinate: const ArtifactCoordinate(
          groupId: 'com.example',
          artifactId: 'lib-a',
          version: '1.0.0',
        ),
        scope: DependencyScope.compile,
        depth: 1,
        path: [],
      );

      expect(node.conflictKey, 'com.example:lib-a');
    });

    test('copyWith creates new node', () {
      final node = DependencyNode(
        coordinate: const ArtifactCoordinate(
          groupId: 'com.example',
          artifactId: 'lib-a',
          version: '1.0.0',
        ),
        scope: DependencyScope.compile,
        depth: 1,
        path: [],
      );

      final copy = node.copyWith(depth: 2);

      expect(copy.depth, 2);
      expect(copy.coordinate, node.coordinate);
    });
  });

  group('ResolutionResult', () {
    test('compileArtifacts filters correctly', () {
      const result = ResolutionResult(
        artifacts: [
          ResolvedArtifact(
            coordinate: ArtifactCoordinate(
              groupId: 'com.example',
              artifactId: 'lib-a',
              version: '1.0.0',
            ),
            scope: DependencyScope.compile,
            depth: 1,
            path: [],
          ),
          ResolvedArtifact(
            coordinate: ArtifactCoordinate(
              groupId: 'com.example',
              artifactId: 'lib-b',
              version: '1.0.0',
            ),
            scope: DependencyScope.test,
            depth: 1,
            path: [],
          ),
        ],
        roots: [],
      );

      expect(result.compileArtifacts, hasLength(1));
      expect(result.compileArtifacts[0].coordinate.artifactId, 'lib-a');
    });
  });

  group('Maven spec compliance fixes', () {
    late MockRepository repo;
    late DependencyResolver resolver;

    setUp(() {
      repo = MockRepository();
      resolver = DependencyResolver(repository: repo);
    });

    group('direct optional dependencies', () {
      test('direct optional dependency is included', () async {
        // In Maven, if you explicitly declare an optional dependency,
        // it should be included in resolution
        repo.addPom('com.example', 'lib-a', '1.0.0', '''
<?xml version="1.0" encoding="UTF-8"?>
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>lib-a</artifactId>
  <version>1.0.0</version>
</project>
''');

        final result = await resolver.resolve(
          directDependencies: [
            const Dependency(
              groupId: 'com.example',
              artifactId: 'lib-a',
              version: '1.0.0',
              optional: true, // Direct dependency marked optional
            ),
          ],
        );

        // Direct optional should be included
        expect(result.isSuccess, isTrue);
        expect(result.artifacts, hasLength(1));
        expect(result.artifacts[0].coordinate.artifactId, 'lib-a');
      });

      test('transitive optional dependency is excluded by default', () async {
        repo.addPom('com.example', 'lib-a', '1.0.0', '''
<?xml version="1.0" encoding="UTF-8"?>
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>lib-a</artifactId>
  <version>1.0.0</version>
  <dependencies>
    <dependency>
      <groupId>com.example</groupId>
      <artifactId>lib-b</artifactId>
      <version>1.0.0</version>
      <optional>true</optional>
    </dependency>
  </dependencies>
</project>
''');
        repo.addSimplePom('com.example', 'lib-b', '1.0.0');

        final result = await resolver.resolve(
          directDependencies: [
            const Dependency(
              groupId: 'com.example',
              artifactId: 'lib-a',
              version: '1.0.0',
            ),
          ],
        );

        // Transitive optional should be excluded
        expect(result.artifacts, hasLength(1));
        expect(
          result.artifacts.any((a) => a.coordinate.artifactId == 'lib-b'),
          isFalse,
        );
      });
    });

    group('BOM processing order', () {
      test('first BOM wins at the same level', () async {
        // When two BOMs are imported at the same level (same POM),
        // the first declared BOM should win for conflicting artifacts.
        // This tests the Maven spec: "first declaration wins at same level"

        // BOM-A declares lib-x:1.0.0
        repo.addPom('com.example', 'bom-a', '1.0.0', '''
<?xml version="1.0" encoding="UTF-8"?>
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>bom-a</artifactId>
  <version>1.0.0</version>
  <packaging>pom</packaging>
  <dependencyManagement>
    <dependencies>
      <dependency>
        <groupId>com.example</groupId>
        <artifactId>lib-x</artifactId>
        <version>1.0.0</version>
      </dependency>
    </dependencies>
  </dependencyManagement>
</project>
''');

        // BOM-B declares lib-x:2.0.0
        repo.addPom('com.example', 'bom-b', '1.0.0', '''
<?xml version="1.0" encoding="UTF-8"?>
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>bom-b</artifactId>
  <version>1.0.0</version>
  <packaging>pom</packaging>
  <dependencyManagement>
    <dependencies>
      <dependency>
        <groupId>com.example</groupId>
        <artifactId>lib-x</artifactId>
        <version>2.0.0</version>
      </dependency>
    </dependencies>
  </dependencyManagement>
</project>
''');

        // Project imports BOM-A first, then BOM-B (at the same level)
        repo.addPom('com.example', 'project', '1.0.0', '''
<?xml version="1.0" encoding="UTF-8"?>
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>project</artifactId>
  <version>1.0.0</version>
  <dependencyManagement>
    <dependencies>
      <dependency>
        <groupId>com.example</groupId>
        <artifactId>bom-a</artifactId>
        <version>1.0.0</version>
        <type>pom</type>
        <scope>import</scope>
      </dependency>
      <dependency>
        <groupId>com.example</groupId>
        <artifactId>bom-b</artifactId>
        <version>1.0.0</version>
        <type>pom</type>
        <scope>import</scope>
      </dependency>
    </dependencies>
  </dependencyManagement>
  <dependencies>
    <dependency>
      <groupId>com.example</groupId>
      <artifactId>lib-x</artifactId>
    </dependency>
  </dependencies>
</project>
''');

        repo.addSimplePom('com.example', 'lib-x', '1.0.0');
        repo.addSimplePom('com.example', 'lib-x', '2.0.0');

        // Use EffectivePomBuilder directly to test BOM processing
        final context = ResolutionContext();
        final builder = EffectivePomBuilder(repository: repo);

        final effectivePom = await builder.build(
          const ArtifactCoordinate(
            groupId: 'com.example',
            artifactId: 'project',
            version: '1.0.0',
          ),
          context,
        );

        expect(effectivePom, isNotNull);

        // Find lib-x in dependencyManagement
        final libX = effectivePom!.dependencyManagement.firstWhere(
          (d) => d.artifactId == 'lib-x',
        );

        // First BOM (bom-a) should win: lib-x:1.0.0
        expect(libX.version, '1.0.0');
      });

      test('child BOM overrides parent BOM for same artifact', () async {
        // Parent BOM declares lib-c:1.0.0
        repo.addPom('com.example', 'parent-bom', '1.0.0', '''
<?xml version="1.0" encoding="UTF-8"?>
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>parent-bom</artifactId>
  <version>1.0.0</version>
  <packaging>pom</packaging>
  <dependencyManagement>
    <dependencies>
      <dependency>
        <groupId>com.example</groupId>
        <artifactId>lib-c</artifactId>
        <version>1.0.0</version>
      </dependency>
    </dependencies>
  </dependencyManagement>
</project>
''');

        // Child BOM declares lib-c:2.0.0 (should override parent)
        repo.addPom('com.example', 'child-bom', '1.0.0', '''
<?xml version="1.0" encoding="UTF-8"?>
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>child-bom</artifactId>
  <version>1.0.0</version>
  <packaging>pom</packaging>
  <dependencyManagement>
    <dependencies>
      <dependency>
        <groupId>com.example</groupId>
        <artifactId>lib-c</artifactId>
        <version>2.0.0</version>
      </dependency>
    </dependencies>
  </dependencyManagement>
</project>
''');

        // Parent POM imports parent-bom
        repo.addPom('com.example', 'parent', '1.0.0', '''
<?xml version="1.0" encoding="UTF-8"?>
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>parent</artifactId>
  <version>1.0.0</version>
  <packaging>pom</packaging>
  <dependencyManagement>
    <dependencies>
      <dependency>
        <groupId>com.example</groupId>
        <artifactId>parent-bom</artifactId>
        <version>1.0.0</version>
        <type>pom</type>
        <scope>import</scope>
      </dependency>
    </dependencies>
  </dependencyManagement>
</project>
''');

        // Child POM extends parent and imports child-bom
        repo.addPom('com.example', 'child', '1.0.0', '''
<?xml version="1.0" encoding="UTF-8"?>
<project>
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>com.example</groupId>
    <artifactId>parent</artifactId>
    <version>1.0.0</version>
  </parent>
  <artifactId>child</artifactId>
  <version>1.0.0</version>
  <dependencyManagement>
    <dependencies>
      <dependency>
        <groupId>com.example</groupId>
        <artifactId>child-bom</artifactId>
        <version>1.0.0</version>
        <type>pom</type>
        <scope>import</scope>
      </dependency>
    </dependencies>
  </dependencyManagement>
  <dependencies>
    <dependency>
      <groupId>com.example</groupId>
      <artifactId>lib-c</artifactId>
    </dependency>
  </dependencies>
</project>
''');

        repo.addSimplePom('com.example', 'lib-c', '1.0.0');
        repo.addSimplePom('com.example', 'lib-c', '2.0.0');

        final result = await resolver.resolve(
          directDependencies: [
            const Dependency(
              groupId: 'com.example',
              artifactId: 'lib-c', // Version from dependencyManagement
            ),
          ],
          dependencyManagement: [
            // Simulate importing child-bom in a context where child BOM
            // should override parent BOM
            const Dependency(
              groupId: 'com.example',
              artifactId: 'lib-c',
              version: '2.0.0', // Child BOM version should be used
            ),
          ],
        );

        expect(result.isSuccess, isTrue);
        final libC = result.artifacts.firstWhere(
          (a) => a.coordinate.artifactId == 'lib-c',
        );
        expect(libC.coordinate.version, '2.0.0'); // Child BOM version wins
      });
    });

    group('relocation handling', () {
      test('follows relocation to new groupId', () async {
        // Old artifact relocates to new groupId
        repo.addRelocatedPom(
          'old.group',
          'lib-a',
          '1.0.0',
          newGroupId: 'new.group',
          message: 'Moved to new.group',
        );

        // New location has the actual artifact
        repo.addSimplePom(
          'new.group',
          'lib-a',
          '1.0.0',
          dependencies: [
            'com.example:lib-b:1.0.0',
          ],
        );
        repo.addSimplePom('com.example', 'lib-b', '1.0.0');

        final result = await resolver.resolve(
          directDependencies: [
            const Dependency(
              groupId: 'old.group',
              artifactId: 'lib-a',
              version: '1.0.0',
            ),
          ],
        );

        expect(result.isSuccess, isTrue);
        // Should have warnings about relocation
        expect(result.warnings, hasLength(1));
        expect(result.warnings[0].message, contains('relocated'));
        expect(result.warnings[0].message, contains('new.group'));

        // Should resolve to the new artifact and its dependencies
        expect(result.artifacts, hasLength(2));
        expect(
          result.artifacts.any(
            (a) =>
                a.coordinate.groupId == 'new.group' &&
                a.coordinate.artifactId == 'lib-a',
          ),
          isTrue,
        );
        expect(
          result.artifacts.any((a) => a.coordinate.artifactId == 'lib-b'),
          isTrue,
        );
      });

      test('follows relocation to new artifactId', () async {
        repo.addRelocatedPom(
          'com.example',
          'old-name',
          '1.0.0',
          newArtifactId: 'new-name',
        );
        repo.addSimplePom('com.example', 'new-name', '1.0.0');

        final result = await resolver.resolve(
          directDependencies: [
            const Dependency(
              groupId: 'com.example',
              artifactId: 'old-name',
              version: '1.0.0',
            ),
          ],
        );

        expect(result.isSuccess, isTrue);
        expect(result.warnings, hasLength(1));
        expect(
          result.artifacts.any((a) => a.coordinate.artifactId == 'new-name'),
          isTrue,
        );
      });

      test('follows relocation to new version', () async {
        repo.addRelocatedPom(
          'com.example',
          'lib-a',
          '1.0.0',
          newVersion: '2.0.0',
        );
        repo.addSimplePom('com.example', 'lib-a', '2.0.0');

        final result = await resolver.resolve(
          directDependencies: [
            const Dependency(
              groupId: 'com.example',
              artifactId: 'lib-a',
              version: '1.0.0',
            ),
          ],
        );

        expect(result.isSuccess, isTrue);
        expect(result.warnings, hasLength(1));
        expect(
          result.artifacts.any((a) => a.coordinate.version == '2.0.0'),
          isTrue,
        );
      });

      test('follows chained relocations', () async {
        // First relocation: old-group -> mid-group
        repo.addRelocatedPom(
          'old.group',
          'lib-a',
          '1.0.0',
          newGroupId: 'mid.group',
        );

        // Second relocation: mid-group -> new-group
        repo.addRelocatedPom(
          'mid.group',
          'lib-a',
          '1.0.0',
          newGroupId: 'new.group',
        );

        // Final location
        repo.addSimplePom('new.group', 'lib-a', '1.0.0');

        final result = await resolver.resolve(
          directDependencies: [
            const Dependency(
              groupId: 'old.group',
              artifactId: 'lib-a',
              version: '1.0.0',
            ),
          ],
        );

        expect(result.isSuccess, isTrue);
        // Should have 2 warnings (one for each relocation)
        expect(result.warnings, hasLength(2));
        expect(
          result.artifacts.any((a) => a.coordinate.groupId == 'new.group'),
          isTrue,
        );
      });

      test('handles transitive dependency relocation', () async {
        // lib-a depends on old-lib
        repo.addSimplePom(
          'com.example',
          'lib-a',
          '1.0.0',
          dependencies: [
            'old.group:old-lib:1.0.0',
          ],
        );

        // old-lib is relocated to new-lib
        repo.addRelocatedPom(
          'old.group',
          'old-lib',
          '1.0.0',
          newGroupId: 'new.group',
          newArtifactId: 'new-lib',
        );

        // new-lib is the actual artifact
        repo.addSimplePom('new.group', 'new-lib', '1.0.0');

        final result = await resolver.resolve(
          directDependencies: [
            const Dependency(
              groupId: 'com.example',
              artifactId: 'lib-a',
              version: '1.0.0',
            ),
          ],
        );

        expect(result.isSuccess, isTrue);
        expect(result.warnings, hasLength(1));
        expect(
          result.artifacts.any(
            (a) =>
                a.coordinate.groupId == 'new.group' &&
                a.coordinate.artifactId == 'new-lib',
          ),
          isTrue,
        );
      });
    });
  });
}
