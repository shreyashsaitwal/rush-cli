String getRushYamlTemp(String name, bool enableKt) {
  return '''
version: '1.0'

android:
  compile_sdk: 31
  min_sdk: 7
${enableKt ? _getKtField() : ''}
# desugar:
#  src_files: false
#  deps: false

# deps:
#   - runtime: 'example.jar'
#   - runtime: 'com.example:foo-bar:1.2.3'
''';
}

String _getKtField() {
  return '''

kotlin:
  enable: true
  version: 'latest-stable'
''';
}
