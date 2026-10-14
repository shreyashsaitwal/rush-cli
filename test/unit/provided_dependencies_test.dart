import 'package:rush/src/commands/migrate/provided_dependencies.dart';
import 'package:test/test.dart';

void main() {
  test('moves provided dependencies to dependencies placed as provided', () {
    expect(withProvidedDependenciesAsLibraries('''
version: '1.0'

# Libraries to bundle.
dependencies:
- com.google.code.gson:gson:2.8.9

# Compile-only libraries.
provided_dependencies:
- com.google.guava:guava:33.3.1-android
- com.google.code.gson:gson:2.8.9
- helper.jar
'''), '''
version: '1.0'

# Libraries to bundle.
dependencies:
- com.google.code.gson:gson:2.8.9
- com.google.guava:guava:33.3.1-android
- helper.jar

libraries:
  com.google.guava:guava: provided
  com.google.code.gson:gson: provided
  helper.jar: provided
''');
  });

  test('keeps the libraries rush.yml already places', () {
    expect(withProvidedDependenciesAsLibraries('''
provided_dependencies:
- com.google.guava:guava:33.3.1-android
libraries:
  com.google.guava:guava: shared
  com.google.code.gson:gson: exclude
'''), '''
libraries:
  com.google.guava:guava: shared
  com.google.code.gson:gson: exclude
dependencies:
  - com.google.guava:guava:33.3.1-android
''');
  });
}
