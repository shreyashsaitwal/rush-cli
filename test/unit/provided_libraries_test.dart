import 'package:rush/src/resolver/provided_libraries.dart';
import 'package:test/test.dart';

void main() {
  const graph = {
    'g:app:1': ['g:client:1', 'g:json:1'],
    'g:client:1': ['g:reflect:1', 'g:json:1'],
    'g:reflect:1': ['g:metadata:1', 'g:stdlib:1'],
    'g:metadata:1': <String>[],
    'g:json:1': ['g:stdlib:1'],
    'g:stdlib:1': <String>[],
    'g:host:1': ['g:host-base:1'],
    'g:host-base:1': <String>[],
  };

  Set<String> provided(Set<String> libraries,
          {List<String> roots = const ['g:app:1']}) =>
      providedOnly(roots: roots, dependencies: graph, provided: libraries);

  test('provides a library and what only it needs', () {
    expect(provided({'g:reflect'}), {'g:reflect:1', 'g:metadata:1'});
  });

  test('ships what a shipped library also needs', () {
    expect(
        provided({'g:client'}), {'g:client:1', 'g:reflect:1', 'g:metadata:1'});
  });

  test('provides a direct dependency and what only it needs', () {
    expect(provided({'g:host'}, roots: ['g:app:1', 'g:host:1']),
        {'g:host:1', 'g:host-base:1'});
  });

  test('provides nothing without provided libraries', () {
    expect(provided({}), isEmpty);
  });

  test('counts a multiplatform variant as its library', () {
    expect(variantKeys('androidx.annotation:annotation'), [
      'androidx.annotation:annotation',
      'androidx.annotation:annotation-jvm',
      'androidx.annotation:annotation-android',
    ]);
  });
}
