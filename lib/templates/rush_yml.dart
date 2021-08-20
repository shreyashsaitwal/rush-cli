String getRushYamlTemp(
    String name, String versionName, String author, bool enableKt) {
  return '''
name: $name
description: |
  **$name**: A new AI2 extension.
  Built with 💖 & Rush.
authors: [ $author ]

version:
  number: auto
  name: '$versionName'

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
