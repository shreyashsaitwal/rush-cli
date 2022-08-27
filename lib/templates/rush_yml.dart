String getRushYamlTemp(String name, bool enableKt) {
  return '''
version: '1.0'

android:
  compile_sdk: 31
  min_sdk: 7
${enableKt ? _getKtField() : ''}
# desugar:
#   src_files: false
#   deps: false

# dependencies:
# - example.jar
# - com.example:foo-bar:1.2.3
''';
}

String _getKtField() {
  return '''

kotlin:
  enable: true
  version: '1.7.10'
''';
}
