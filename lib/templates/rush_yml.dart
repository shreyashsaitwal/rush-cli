String getRushYamlTemp(String name, bool enableKt) {
  return '''
name: $name
description: Extension component for **Kot**. Built with <3 & Rush.
version: '1.0'

build:
  release:
    optimize: true
${enableKt ? _getKtField() : ''}
  desugar:
    enable: false
    desugar_deps: false

assets:
  icon: icon.png  # This can be a URL or a local image in 'assets' folder.
  # other: [ 'asset01', 'asset02' ]
''';
}

String _getKtField() {
  return '''

  kotlin:
    enable: true
''';
}
