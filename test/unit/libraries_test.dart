import 'package:rush/src/commands/build/libraries.dart';
import 'package:test/test.dart';

void main() {
  group('assignSharedClasses', () {
    test('ships a class only from the jar with the most classes', () {
      expect(
          assignSharedClasses({
            'small': ['a/Shared.class', 'a/Small.class'],
            'large': ['a/Shared.class', 'a/Large.class', 'a/Other.class'],
          }),
          {
            'large': {'a/Shared.class', 'a/Large.class', 'a/Other.class'},
            'small': {'a/Small.class'},
          });
    });

    test('keeps dependency order between jars of the same size', () {
      expect(
          assignSharedClasses({
            'first': ['a/Shared.class'],
            'second': ['a/Shared.class'],
          }),
          {
            'first': {'a/Shared.class'}
          });
    });

    test('lists jars from the most classes to the fewest', () {
      expect(
          assignSharedClasses({
            'one': ['a/A.class'],
            'three': ['b/A.class', 'b/B.class', 'b/C.class'],
            'two': ['c/A.class', 'c/B.class'],
          }).keys,
          ['three', 'two', 'one']);
    });
  });

  group('duplicateLibraries', () {
    test('groups AARs that declare the same package', () {
      expect(
          duplicateLibraries({
            'remote.aar': 'androidx.core',
            'local.aar': 'androidx.core',
            'other.aar': 'androidx.media',
          }),
          {
            'androidx.core': ['remote.aar', 'local.aar']
          });
    });

    test('finds nothing when every package is distinct', () {
      expect(duplicateLibraries({'a.aar': 'a', 'b.aar': 'b'}), isEmpty);
    });
  });
}
