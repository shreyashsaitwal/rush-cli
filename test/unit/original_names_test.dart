import 'package:rush/src/commands/build/original_names.dart';
import 'package:test/test.dart';

List<String> _errors(Iterable<String> originalNames, Set<String> privateClasses,
        [Map<String, Set<String>> nativeNames = const {}]) =>
    [
      for (final problem in originalNameProblems(
          originalNames: originalNames,
          privateClasses: privateClasses,
          nativeNames: nativeNames))
        if (problem.isError) problem.message,
    ];

void main() {
  test('accepts listed packages that private libraries have', () {
    expect(_errors(['lib.store'], {'lib/store/Counter', 'lib/other/Thing'}),
        isEmpty);
  });

  test('refuses listed packages no private library has', () {
    expect(
        _errors(['lib.store', 'lib.gone'],
            {'lib/store/Counter', 'lib/gone/sub/Thing'}),
        [
          'original_names lists lib.gone, but no private library has classes in '
              'it. Remove it from rush.yml.',
        ]);
  });

  test('accepts native libraries naming listed packages', () {
    expect(
        _errors([
          'lib.store'
        ], {
          'lib/store/Counter'
        }, {
          'g:store:1': {'lib/store/Counter'},
        }),
        isEmpty);
  });

  test('names the packages native libraries need kept', () {
    expect(
        _errors([
          'lib.store'
        ], {
          'lib/store/Counter',
          'lib/jni/Bridge',
          'lib/jni/Loader',
          'kotlin/Unit'
        }, {
          'g:store:1': {
            'lib/store/Counter',
            'lib/jni/Bridge',
            'lib/jni/Loader',
            'kotlin/Unit'
          },
        }),
        [
          'g:store:1 has native libraries that find classes in kotlin and '
              'lib.jni by their original names. Keep those names in rush.yml:\n'
              '\n'
              'original_names:\n'
              '- kotlin\n'
              '- lib.jni\n'
              '\n'
              'or place it as shared: `libraries: {g:store: shared}`.',
        ]);
  });
}
