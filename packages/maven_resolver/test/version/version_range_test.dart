// Tests for Maven version range parsing and matching

import 'package:maven_resolver/src/version/maven_version.dart';
import 'package:maven_resolver/src/version/version_range.dart';
import 'package:test/test.dart';

void main() {
  group('VersionRange', () {
    MavenVersion v(String s) => MavenVersion.parse(s);

    group('SoftRequirement', () {
      test('parses plain version as soft requirement', () {
        final range = VersionRange.parse('1.0');
        expect(range, isA<SoftRequirement>());
        expect(range.isSoft, isTrue);
        expect(range.isHard, isFalse);
      });

      test('contains only exact version', () {
        final range = VersionRange.parse('1.0');
        expect(range.contains(v('1.0')), isTrue);
        expect(range.contains(v('1.0.0')), isTrue); // Normalized equal
        expect(range.contains(v('1.1')), isFalse);
        expect(range.contains(v('0.9')), isFalse);
      });

      test('toString returns version', () {
        final range = VersionRange.parse('1.0.5');
        expect(range.toString(), equals('1.0.5'));
      });
    });

    group('HardRequirement - exact version', () {
      test('parses [version] as exact requirement', () {
        final range = VersionRange.parse('[1.0]');
        expect(range, isA<HardRequirement>());
        expect(range.isSoft, isFalse);
        expect(range.isHard, isTrue);
      });

      test('contains only exact version', () {
        final range = VersionRange.parse('[1.0]');
        expect(range.contains(v('1.0')), isTrue);
        expect(range.contains(v('1.0.0')), isTrue);
        expect(range.contains(v('1.1')), isFalse);
        expect(range.contains(v('0.9')), isFalse);
      });

      test('toString returns [version]', () {
        final range = VersionRange.parse('[1.0]');
        expect(range.toString(), equals('[1.0]'));
      });
    });

    group('HardRequirement - inclusive range', () {
      test('parses [min,max] as inclusive range', () {
        final range = VersionRange.parse('[1.0,2.0]');
        expect(range, isA<HardRequirement>());
      });

      test('contains versions in inclusive range', () {
        final range = VersionRange.parse('[1.0,2.0]');
        expect(range.contains(v('0.9')), isFalse);
        expect(range.contains(v('1.0')), isTrue);
        expect(range.contains(v('1.5')), isTrue);
        expect(range.contains(v('2.0')), isTrue);
        expect(range.contains(v('2.1')), isFalse);
      });
    });

    group('HardRequirement - exclusive range', () {
      test('parses (min,max) as exclusive range', () {
        final range = VersionRange.parse('(1.0,2.0)');
        expect(range, isA<HardRequirement>());
      });

      test('contains versions in exclusive range', () {
        final range = VersionRange.parse('(1.0,2.0)');
        expect(range.contains(v('1.0')), isFalse);
        expect(range.contains(v('1.0.1')), isTrue);
        expect(range.contains(v('1.5')), isTrue);
        expect(range.contains(v('1.9.9')), isTrue);
        expect(range.contains(v('2.0')), isFalse);
      });
    });

    group('HardRequirement - mixed brackets', () {
      test('[min,max) - inclusive min, exclusive max', () {
        final range = VersionRange.parse('[1.0,2.0)');
        expect(range.contains(v('1.0')), isTrue);
        expect(range.contains(v('1.5')), isTrue);
        expect(range.contains(v('2.0')), isFalse);
      });

      test('(min,max] - exclusive min, inclusive max', () {
        final range = VersionRange.parse('(1.0,2.0]');
        expect(range.contains(v('1.0')), isFalse);
        expect(range.contains(v('1.5')), isTrue);
        expect(range.contains(v('2.0')), isTrue);
      });
    });

    group('HardRequirement - unbounded', () {
      test('[min,) - at least', () {
        final range = VersionRange.parse('[1.0,)');
        expect(range.contains(v('0.9')), isFalse);
        expect(range.contains(v('1.0')), isTrue);
        expect(range.contains(v('999.0')), isTrue);
      });

      test('(min,) - greater than', () {
        final range = VersionRange.parse('(1.0,)');
        expect(range.contains(v('1.0')), isFalse);
        expect(range.contains(v('1.0.1')), isTrue);
        expect(range.contains(v('999.0')), isTrue);
      });

      test('(,max] - at most', () {
        final range = VersionRange.parse('(,2.0]');
        expect(range.contains(v('0.1')), isTrue);
        expect(range.contains(v('2.0')), isTrue);
        expect(range.contains(v('2.1')), isFalse);
      });

      test('(,max) - less than', () {
        final range = VersionRange.parse('(,2.0)');
        expect(range.contains(v('0.1')), isTrue);
        expect(range.contains(v('1.9.9')), isTrue);
        expect(range.contains(v('2.0')), isFalse);
      });
    });

    group('MultiRange', () {
      test('parses comma-separated ranges', () {
        final range = VersionRange.parse('(,1.0],[1.5,)');
        expect(range, isA<MultiRange>());
      });

      test('contains versions in either range', () {
        final range = VersionRange.parse('(,1.0],[1.5,)');
        expect(range.contains(v('0.5')), isTrue);
        expect(range.contains(v('1.0')), isTrue);
        expect(range.contains(v('1.2')), isFalse);
        expect(range.contains(v('1.5')), isTrue);
        expect(range.contains(v('2.0')), isTrue);
      });

      test('toString returns original format', () {
        final range = VersionRange.parse('(,1.0],[1.5,)');
        expect(range.toString(), equals('(,1.0],[1.5,)'));
      });
    });

    group('selectBest', () {
      test('selects highest version in range', () {
        final range = VersionRange.parse('[1.0,2.0)');
        final available =
            ['0.9', '1.0', '1.5', '1.9', '2.0', '2.1'].map(v).toList();
        expect(range.selectBest(available), equals(v('1.9')));
      });

      test('returns null when no version matches', () {
        final range = VersionRange.parse('[3.0,4.0)');
        final available = ['1.0', '2.0'].map(v).toList();
        expect(range.selectBest(available), isNull);
      });

      test('handles soft requirement', () {
        final range = VersionRange.parse('1.5');
        final available = ['1.0', '1.5', '2.0'].map(v).toList();
        expect(range.selectBest(available), equals(v('1.5')));
      });

      test('handles exact version requirement', () {
        final range = VersionRange.parse('[1.5]');
        final available = ['1.0', '1.5', '2.0'].map(v).toList();
        expect(range.selectBest(available), equals(v('1.5')));
      });
    });

    group('intersect', () {
      test('intersects two overlapping ranges', () {
        final r1 = VersionRange.parse('[1.0,3.0]');
        final r2 = VersionRange.parse('[2.0,4.0]');
        final intersection = r1.intersect(r2);

        expect(intersection, isNotNull);
        expect(intersection!.contains(v('1.5')), isFalse);
        expect(intersection.contains(v('2.0')), isTrue);
        expect(intersection.contains(v('3.0')), isTrue);
        expect(intersection.contains(v('3.5')), isFalse);
      });

      test('returns null for non-overlapping ranges', () {
        final r1 = VersionRange.parse('[1.0,2.0]');
        final r2 = VersionRange.parse('[3.0,4.0]');
        expect(r1.intersect(r2), isNull);
      });

      test('handles inclusive/exclusive boundaries', () {
        final r1 = VersionRange.parse('[1.0,2.0)');
        final r2 = VersionRange.parse('(1.5,3.0]');
        final intersection = r1.intersect(r2);

        expect(intersection, isNotNull);
        expect(intersection!.contains(v('1.5')), isFalse);
        expect(intersection.contains(v('1.6')), isTrue);
        expect(intersection.contains(v('2.0')), isFalse);
      });

      test('returns null for touching but non-overlapping', () {
        final r1 = VersionRange.parse('[1.0,2.0)');
        final r2 = VersionRange.parse('[2.0,3.0]');
        expect(r1.intersect(r2), isNull);
      });

      test('soft requirement intersection', () {
        final soft = VersionRange.parse('1.5');
        final hard = VersionRange.parse('[1.0,2.0]');
        final intersection = soft.intersect(hard);

        expect(intersection, isNotNull);
        expect(intersection, isA<SoftRequirement>());
      });

      test('soft requirement outside hard range', () {
        final soft = VersionRange.parse('3.0');
        final hard = VersionRange.parse('[1.0,2.0]');
        final intersection = soft.intersect(hard);

        // Hard requirement wins
        expect(intersection, isA<HardRequirement>());
      });
    });

    group('edge cases', () {
      test('empty range string throws', () {
        expect(() => VersionRange.parse(''), throwsFormatException);
        expect(() => VersionRange.parse('   '), throwsFormatException);
      });

      test('invalid range syntax throws', () {
        expect(() => VersionRange.parse('[1.0'), throwsFormatException);
        // Note: '1.0]' parses as a soft requirement for version "1.0]"
        // which is unusual but technically valid as a version string
      });

      test('inverted range throws', () {
        expect(() => VersionRange.parse('[2.0,1.0]'), throwsFormatException);
      });

      test('non-inclusive exact version throws', () {
        expect(() => VersionRange.parse('(1.0)'), throwsFormatException);
        expect(() => VersionRange.parse('[1.0)'), throwsFormatException);
        expect(() => VersionRange.parse('(1.0]'), throwsFormatException);
      });

      test('handles whitespace in version', () {
        final range = VersionRange.parse(' 1.0 ');
        expect(range.contains(v('1.0')), isTrue);
      });

      test('handles complex multi-range', () {
        final range = VersionRange.parse('(,1.0),[1.5,2.0),(2.5,)');
        expect(range, isA<MultiRange>());
        expect(range.contains(v('0.5')), isTrue);
        expect(range.contains(v('1.0')), isFalse);
        expect(range.contains(v('1.2')), isFalse);
        expect(range.contains(v('1.5')), isTrue);
        expect(range.contains(v('2.0')), isFalse);
        expect(range.contains(v('2.3')), isFalse);
        expect(range.contains(v('2.6')), isTrue);
      });
    });

    group('real-world examples', () {
      test('Spring Boot style: [2.0.0,3.0.0)', () {
        final range = VersionRange.parse('[2.0.0,3.0.0)');
        expect(range.contains(v('1.5.22')), isFalse);
        expect(range.contains(v('2.0.0')), isTrue);
        expect(range.contains(v('2.7.8')), isTrue);
        expect(range.contains(v('3.0.0')), isFalse);
        expect(range.contains(v('3.0.1')), isFalse);
      });

      test('Exact version: [4.1.77.Final]', () {
        final range = VersionRange.parse('[4.1.77.Final]');
        expect(range.contains(v('4.1.77.Final')), isTrue);
        // Note: 4.1.77.Final normalizes to 4.1.77 (Final is a null qualifier)
        // so they are equal according to Maven spec
        expect(range.contains(v('4.1.77')), isTrue);
        expect(range.contains(v('4.1.78.Final')), isFalse);
      });

      test('Minimum version: [1.8,)', () {
        final range = VersionRange.parse('[1.8,)');
        expect(range.contains(v('1.7')), isFalse);
        expect(range.contains(v('1.8')), isTrue);
        expect(range.contains(v('11')), isTrue);
        expect(range.contains(v('17')), isTrue);
      });
    });
  });
}
