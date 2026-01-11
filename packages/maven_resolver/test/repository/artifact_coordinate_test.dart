import 'package:maven_resolver/maven_resolver.dart';
import 'package:test/test.dart';

void main() {
  group('ArtifactCoordinate', () {
    group('parse', () {
      test('parses 3-part coordinate', () {
        final coord = ArtifactCoordinate.parse('org.example:my-lib:1.0.0');
        expect(coord.groupId, 'org.example');
        expect(coord.artifactId, 'my-lib');
        expect(coord.version, '1.0.0');
        expect(coord.packaging, 'jar');
        expect(coord.classifier, isNull);
      });

      test('parses 4-part coordinate', () {
        final coord = ArtifactCoordinate.parse('org.example:my-lib:pom:1.0.0');
        expect(coord.groupId, 'org.example');
        expect(coord.artifactId, 'my-lib');
        expect(coord.version, '1.0.0');
        expect(coord.packaging, 'pom');
        expect(coord.classifier, isNull);
      });

      test('parses 5-part coordinate', () {
        final coord =
            ArtifactCoordinate.parse('org.example:my-lib:jar:sources:1.0.0');
        expect(coord.groupId, 'org.example');
        expect(coord.artifactId, 'my-lib');
        expect(coord.version, '1.0.0');
        expect(coord.packaging, 'jar');
        expect(coord.classifier, 'sources');
      });

      test('parses 5-part coordinate with empty classifier', () {
        final coord = ArtifactCoordinate.parse('org.example:my-lib:jar::1.0.0');
        expect(coord.classifier, isNull);
      });

      test('throws on invalid coordinate', () {
        expect(
          () => ArtifactCoordinate.parse('invalid'),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => ArtifactCoordinate.parse('a:b'),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => ArtifactCoordinate.parse('a:b:c:d:e:f'),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('groupPath', () {
      test('converts dots to slashes', () {
        const coord = ArtifactCoordinate(
          groupId: 'org.apache.maven',
          artifactId: 'maven-core',
          version: '3.6.0',
        );
        expect(coord.groupPath, 'org/apache/maven');
      });
    });

    group('baseFilename', () {
      test('without classifier', () {
        const coord = ArtifactCoordinate(
          groupId: 'org.example',
          artifactId: 'my-lib',
          version: '1.0.0',
        );
        expect(coord.baseFilename, 'my-lib-1.0.0');
      });

      test('with classifier', () {
        const coord = ArtifactCoordinate(
          groupId: 'org.example',
          artifactId: 'my-lib',
          version: '1.0.0',
          classifier: 'sources',
        );
        expect(coord.baseFilename, 'my-lib-1.0.0-sources');
      });
    });

    group('pomFilename', () {
      test('returns correct POM filename', () {
        const coord = ArtifactCoordinate(
          groupId: 'org.example',
          artifactId: 'my-lib',
          version: '1.0.0',
        );
        expect(coord.pomFilename, 'my-lib-1.0.0.pom');
      });
    });

    group('artifactFilename', () {
      test('uses packaging extension by default', () {
        const coord = ArtifactCoordinate(
          groupId: 'org.example',
          artifactId: 'my-lib',
          version: '1.0.0',
        );
        expect(coord.artifactFilename(), 'my-lib-1.0.0.jar');
      });

      test('allows override extension', () {
        const coord = ArtifactCoordinate(
          groupId: 'org.example',
          artifactId: 'my-lib',
          version: '1.0.0',
        );
        expect(coord.artifactFilename('war'), 'my-lib-1.0.0.war');
      });

      test('includes classifier', () {
        const coord = ArtifactCoordinate(
          groupId: 'org.example',
          artifactId: 'my-lib',
          version: '1.0.0',
          classifier: 'sources',
        );
        expect(coord.artifactFilename(), 'my-lib-1.0.0-sources.jar');
      });
    });

    group('paths', () {
      test('artifactPath', () {
        const coord = ArtifactCoordinate(
          groupId: 'org.example',
          artifactId: 'my-lib',
          version: '1.0.0',
        );
        expect(coord.artifactPath, 'org/example/my-lib/1.0.0');
      });

      test('pomPath', () {
        const coord = ArtifactCoordinate(
          groupId: 'org.example',
          artifactId: 'my-lib',
          version: '1.0.0',
        );
        expect(coord.pomPath, 'org/example/my-lib/1.0.0/my-lib-1.0.0.pom');
      });

      test('artifactFilePath', () {
        const coord = ArtifactCoordinate(
          groupId: 'org.example',
          artifactId: 'my-lib',
          version: '1.0.0',
        );
        expect(
          coord.artifactFilePath(),
          'org/example/my-lib/1.0.0/my-lib-1.0.0.jar',
        );
      });
    });

    group('isSnapshot', () {
      test('returns true for SNAPSHOT versions', () {
        const coord = ArtifactCoordinate(
          groupId: 'org.example',
          artifactId: 'my-lib',
          version: '1.0.0-SNAPSHOT',
        );
        expect(coord.isSnapshot, isTrue);
      });

      test('returns false for release versions', () {
        const coord = ArtifactCoordinate(
          groupId: 'org.example',
          artifactId: 'my-lib',
          version: '1.0.0',
        );
        expect(coord.isSnapshot, isFalse);
      });
    });

    group('toString', () {
      test('3-part for simple jar', () {
        const coord = ArtifactCoordinate(
          groupId: 'org.example',
          artifactId: 'my-lib',
          version: '1.0.0',
        );
        expect(coord.toString(), 'org.example:my-lib:1.0.0');
      });

      test('4-part for non-jar packaging', () {
        const coord = ArtifactCoordinate(
          groupId: 'org.example',
          artifactId: 'my-lib',
          version: '1.0.0',
          packaging: 'war',
        );
        expect(coord.toString(), 'org.example:my-lib:war:1.0.0');
      });

      test('5-part with classifier', () {
        const coord = ArtifactCoordinate(
          groupId: 'org.example',
          artifactId: 'my-lib',
          version: '1.0.0',
          classifier: 'sources',
        );
        expect(coord.toString(), 'org.example:my-lib:jar:sources:1.0.0');
      });
    });

    group('conflictKey', () {
      test('without classifier', () {
        const coord = ArtifactCoordinate(
          groupId: 'org.example',
          artifactId: 'my-lib',
          version: '1.0.0',
        );
        expect(coord.conflictKey, 'org.example:my-lib');
      });

      test('with classifier', () {
        const coord = ArtifactCoordinate(
          groupId: 'org.example',
          artifactId: 'my-lib',
          version: '1.0.0',
          classifier: 'sources',
        );
        expect(coord.conflictKey, 'org.example:my-lib:sources');
      });
    });

    group('equality', () {
      test('equal coordinates', () {
        const a = ArtifactCoordinate(
          groupId: 'org.example',
          artifactId: 'my-lib',
          version: '1.0.0',
        );
        const b = ArtifactCoordinate(
          groupId: 'org.example',
          artifactId: 'my-lib',
          version: '1.0.0',
        );
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('different versions are not equal', () {
        const a = ArtifactCoordinate(
          groupId: 'org.example',
          artifactId: 'my-lib',
          version: '1.0.0',
        );
        const b = ArtifactCoordinate(
          groupId: 'org.example',
          artifactId: 'my-lib',
          version: '2.0.0',
        );
        expect(a, isNot(equals(b)));
      });
    });

    group('copyWith', () {
      test('copies with new version', () {
        const original = ArtifactCoordinate(
          groupId: 'org.example',
          artifactId: 'my-lib',
          version: '1.0.0',
        );
        final copy = original.copyWith(version: '2.0.0');
        expect(copy.groupId, 'org.example');
        expect(copy.artifactId, 'my-lib');
        expect(copy.version, '2.0.0');
      });
    });
  });
}
