// Tests ported from Maven's ComparableVersionTest.java
// https://github.com/apache/maven/blob/maven-3.9.x/maven-artifact/src/test/java/org/apache/maven/artifact/versioning/ComparableVersionTest.java
//
// Licensed under the Apache License, Version 2.0

import 'package:maven_resolver/src/version/maven_version.dart';
import 'package:test/test.dart';

void main() {
  group('MavenVersion', () {
    MavenVersion parse(String version) {
      final parsed = MavenVersion.parse(version);
      final canonical = parsed.canonical;
      final reparsed = MavenVersion.parse(canonical);

      // Verify that parsing the canonical form gives the same canonical
      expect(
        reparsed.canonical,
        equals(canonical),
        reason:
            'canonical($version) = $canonical -> reparsed: ${reparsed.canonical}',
      );

      return parsed;
    }

    void checkVersionsEqual(String v1, String v2) {
      final c1 = parse(v1);
      final c2 = parse(v2);

      expect(
        c1.compareTo(c2),
        equals(0),
        reason: 'expected $v1 == $v2',
      );
      expect(
        c2.compareTo(c1),
        equals(0),
        reason: 'expected $v2 == $v1',
      );
      expect(
        c1.hashCode,
        equals(c2.hashCode),
        reason: 'expected same hashcode for $v1 and $v2',
      );
      expect(
        c1,
        equals(c2),
        reason: 'expected $v1.equals($v2)',
      );
      expect(
        c2,
        equals(c1),
        reason: 'expected $v2.equals($v1)',
      );
    }

    void checkVersionsOrder(String v1, String v2) {
      final c1 = parse(v1);
      final c2 = parse(v2);

      expect(
        c1.compareTo(c2),
        lessThan(0),
        reason: 'expected $v1 < $v2',
      );
      expect(
        c2.compareTo(c1),
        greaterThan(0),
        reason: 'expected $v2 > $v1',
      );
    }

    void checkVersionsArrayOrder(List<String> versions) {
      final parsed = versions.map(parse).toList();

      for (var i = 1; i < versions.length; i++) {
        final low = parsed[i - 1];
        final lowStr = versions[i - 1];
        for (var j = i; j < versions.length; j++) {
          final high = parsed[j];
          final highStr = versions[j];
          expect(
            low.compareTo(high),
            lessThan(0),
            reason: 'expected $lowStr < $highStr',
          );
          expect(
            high.compareTo(low),
            greaterThan(0),
            reason: 'expected $highStr > $lowStr',
          );
        }
      }
    }

    void checkVersionsArrayEqual(List<String> versions) {
      for (var i = 0; i < versions.length; i++) {
        for (var j = i; j < versions.length; j++) {
          checkVersionsEqual(versions[i], versions[j]);
        }
      }
    }

    group('testVersionsQualifier', () {
      const versionsQualifier = [
        '1-alpha2snapshot',
        '1-alpha2',
        '1-alpha-123',
        '1-beta-2',
        '1-beta123',
        '1-m2',
        '1-m11',
        '1-rc',
        '1-cr2',
        '1-rc123',
        '1-SNAPSHOT',
        '1',
        '1-sp',
        '1-sp2',
        '1-sp123',
        '1-abc',
        '1-def',
        '1-pom-1',
        '1-1-snapshot',
        '1-1',
        '1-2',
        '1-123',
      ];

      test('qualifiers are ordered correctly', () {
        checkVersionsArrayOrder(versionsQualifier);
      });
    });

    group('testVersionsNumber', () {
      const versionsNumber = [
        '2.0',
        '2.0.a',
        '2-1',
        '2.0.2',
        '2.0.123',
        '2.1.0',
        '2.1-a',
        '2.1b',
        '2.1-c',
        '2.1-1',
        '2.1.0.1',
        '2.2',
        '2.123',
        '11.a2',
        '11.a11',
        '11.b2',
        '11.b11',
        '11.m2',
        '11.m11',
        '11',
        '11.a',
        '11b',
        '11c',
        '11m',
      ];

      test('numbers are ordered correctly', () {
        checkVersionsArrayOrder(versionsNumber);
      });
    });

    group('testVersionsEqual', () {
      test('basic equality', () {
        checkVersionsEqual('1', '1');
        checkVersionsEqual('1', '1.0');
        checkVersionsEqual('1', '1.0.0');
        checkVersionsEqual('1.0', '1.0.0');
        checkVersionsEqual('1', '1-0');
        checkVersionsEqual('1', '1.0-0');
        checkVersionsEqual('1.0', '1.0-0');
      });

      test('no separator between number and character', () {
        checkVersionsEqual('1a', '1-a');
        checkVersionsEqual('1a', '1.0-a');
        checkVersionsEqual('1a', '1.0.0-a');
        checkVersionsEqual('1.0a', '1-a');
        checkVersionsEqual('1.0.0a', '1-a');
        checkVersionsEqual('1x', '1-x');
        checkVersionsEqual('1x', '1.0-x');
        checkVersionsEqual('1x', '1.0.0-x');
        checkVersionsEqual('1.0x', '1-x');
        checkVersionsEqual('1.0.0x', '1-x');
      });

      test('aliases', () {
        checkVersionsEqual('1ga', '1');
        checkVersionsEqual('1release', '1');
        checkVersionsEqual('1final', '1');
        checkVersionsEqual('1cr', '1rc');
      });

      test('special aliases a, b, m for alpha, beta, milestone', () {
        checkVersionsEqual('1a1', '1-alpha-1');
        checkVersionsEqual('1b2', '1-beta-2');
        checkVersionsEqual('1m3', '1-milestone-3');
      });

      test('case insensitive', () {
        checkVersionsEqual('1X', '1x');
        checkVersionsEqual('1A', '1a');
        checkVersionsEqual('1B', '1b');
        checkVersionsEqual('1M', '1m');
        checkVersionsEqual('1Ga', '1');
        checkVersionsEqual('1GA', '1');
        checkVersionsEqual('1RELEASE', '1');
        checkVersionsEqual('1release', '1');
        checkVersionsEqual('1RELeaSE', '1');
        checkVersionsEqual('1Final', '1');
        checkVersionsEqual('1FinaL', '1');
        checkVersionsEqual('1FINAL', '1');
        checkVersionsEqual('1Cr', '1Rc');
        checkVersionsEqual('1cR', '1rC');
        checkVersionsEqual('1m3', '1Milestone3');
        checkVersionsEqual('1m3', '1MileStone3');
        checkVersionsEqual('1m3', '1MILESTONE3');
      });
    });

    group('testVersionComparing', () {
      test('basic ordering', () {
        checkVersionsOrder('1', '2');
        checkVersionsOrder('1.5', '2');
        checkVersionsOrder('1', '2.5');
        checkVersionsOrder('1.0', '1.1');
        checkVersionsOrder('1.1', '1.2');
        checkVersionsOrder('1.0.0', '1.1');
        checkVersionsOrder('1.0.1', '1.1');
        checkVersionsOrder('1.1', '1.2.0');
      });

      test('alpha/beta/snapshot ordering', () {
        checkVersionsOrder('1.0-alpha-1', '1.0');
        checkVersionsOrder('1.0-alpha-1', '1.0-alpha-2');
        checkVersionsOrder('1.0-alpha-1', '1.0-beta-1');
        checkVersionsOrder('1.0-beta-1', '1.0-SNAPSHOT');
        checkVersionsOrder('1.0-SNAPSHOT', '1.0');
        checkVersionsOrder('1.0-alpha-1-SNAPSHOT', '1.0-alpha-1');
      });

      test('numeric suffixes', () {
        checkVersionsOrder('1.0', '1.0-1');
        checkVersionsOrder('1.0-1', '1.0-2');
        checkVersionsOrder('1.0.0', '1.0-1');
      });

      test('complex ordering', () {
        checkVersionsOrder('2.0-1', '2.0.1');
        checkVersionsOrder('2.0.1-klm', '2.0.1-lmn');
        checkVersionsOrder('2.0.1', '2.0.1-xyz');
        checkVersionsOrder('2.0.1', '2.0.1-123');
        checkVersionsOrder('2.0.1-xyz', '2.0.1-123');
      });
    });

    group('testMng5568', () {
      test('transitive consistency edge case', () {
        const a = '6.1.0';
        const b = '6.1.0rc3';
        const c = '6.1H.5-beta';

        checkVersionsOrder(b, a); // classical
        checkVersionsOrder(b, c); // b < c
        checkVersionsOrder(a, c);
      });
    });

    group('testMng6572', () {
      test('large number optimization', () {
        const a = '20190126.230843';
        const b = '1234567890.12345';
        const c = '123456789012345.1H.5-beta';
        const d = '12345678901234567890.1H.5-beta';

        checkVersionsOrder(a, b);
        checkVersionsOrder(b, c);
        checkVersionsOrder(a, c);
        checkVersionsOrder(c, d);
        checkVersionsOrder(b, d);
        checkVersionsOrder(a, d);
      });
    });

    group('testVersionEqualWithLeadingZeroes', () {
      test('versions equal with leading zeroes', () {
        const arr = [
          '0000000000000000001',
          '000000000000000001',
          '00000000000000001',
          '0000000000000001',
          '000000000000001',
          '00000000000001',
          '0000000000001',
          '000000000001',
          '00000000001',
          '0000000001',
          '000000001',
          '00000001',
          '0000001',
          '000001',
          '00001',
          '0001',
          '001',
          '01',
          '1',
        ];

        checkVersionsArrayEqual(arr);
      });
    });

    group('testVersionZeroEqualWithLeadingZeroes', () {
      test('zero versions equal with leading zeroes', () {
        const arr = [
          '0000000000000000000',
          '000000000000000000',
          '00000000000000000',
          '0000000000000000',
          '000000000000000',
          '00000000000000',
          '0000000000000',
          '000000000000',
          '00000000000',
          '0000000000',
          '000000000',
          '00000000',
          '0000000',
          '000000',
          '00000',
          '0000',
          '000',
          '00',
          '0',
        ];

        checkVersionsArrayEqual(arr);
      });
    });

    group('testMng6964', () {
      test('qualifiers starting with -0.', () {
        const a = '1-0.alpha';
        const b = '1-0.beta';
        const c = '1';

        checkVersionsOrder(a, c);
        checkVersionsOrder(b, c);
        checkVersionsOrder(a, b);
      });
    });

    group('testLocaleIndependent', () {
      test('case insensitive for all letters', () {
        checkVersionsEqual(
          '1-abcdefghijklmnopqrstuvwxyz',
          '1-ABCDEFGHIJKLMNOPQRSTUVWXYZ',
        );
      });
    });

    group('testMng7644', () {
      test('dot vs hyphen separator edge cases', () {
        for (final x in [
          'abc',
          'alpha',
          'a',
          'beta',
          'b',
          'def',
          'milestone',
          'm',
          'RC',
        ]) {
          // 1.0.0.X1 < 1.0.0-X2 for any string x
          checkVersionsOrder('1.0.0.${x}1', '1.0.0-${x}2');
          // 2.0.X == 2-X == 2.0.0.X for any string x
          checkVersionsEqual('2-$x', '2.0.$x');
          checkVersionsEqual('2-$x', '2.0.0.$x');
          checkVersionsEqual('2.0.$x', '2.0.0.$x');
        }
      });
    });

    group('additional edge cases', () {
      test('empty string handling', () {
        // Empty parts should be treated as null/0
        final v1 = parse('1.0.0');
        final v2 = parse('1');
        expect(v1, equals(v2));
      });

      test('canonical form', () {
        expect(parse('1.0.0').canonical, equals('1'));
        expect(parse('1.0.0-0').canonical, equals('1'));
        expect(parse('1.ga').canonical, equals('1'));
        expect(parse('1.0.FINAL').canonical, equals('1'));
        expect(parse('1-alpha-1').canonical, equals('1-alpha-1'));
      });

      test('operator overloads', () {
        final v1 = parse('1.0');
        final v2 = parse('2.0');
        final v1dup = parse('1.0.0');

        expect(v1 < v2, isTrue);
        expect(v1 <= v2, isTrue);
        expect(v2 > v1, isTrue);
        expect(v2 >= v1, isTrue);
        expect(v1 <= v1dup, isTrue);
        expect(v1 >= v1dup, isTrue);
        expect(v1 == v1dup, isTrue);
      });
    });
  });
}
