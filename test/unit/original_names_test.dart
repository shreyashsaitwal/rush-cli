import 'package:rush/src/commands/build/original_names.dart';
import 'package:test/test.dart';

List<String> _errors(
        Iterable<String> originalNames, Set<String> privateClasses) =>
    [
      for (final problem in originalNameProblems(
          originalNames: originalNames, privateClasses: privateClasses))
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
}
