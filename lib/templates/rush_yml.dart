String getRushYamlTemp(
    String name, String versionName, String author, bool enableKt) {
  return '''
# For a detailed info on this file and supported fields, check out the below link:
# https://github.com/ShreyashSaitwal/rush-cli/wiki/Metadata-File

---
name: $name
description: Extension component for $name. Created using Rush.

version:
  number: auto
  name: '$versionName'

authors:
  - $author

build:
  release:
    # Optimizes the extension on every release build.
    optimize: true
${enableKt ? _getKtField() : ''}
  # If enabled, you will be able to use Java 8 language features in your extension.
  desugar:
    enable: false
    desugar_deps: false

assets:
  # Extension icon. This can be a URL or a local image in 'assets' folder.
  icon: icon.png
  # Extension assets.
  # other:
  #   - my_awesome_asset.anything

# Extension dependencies (JAR).
# deps:
#   - my_awesome_library.jar
''';
}

String _getKtField() {
  return '''

  kotlin:
    enable: true
''';
}
