String getRushYamlTemp(
    String name, String versionName, String author, bool enableKt) {
  return '''
# For a detailed info on this file and supported fields, check
# out this link: https://github.com/ShreyashSaitwal/rush-cli/wiki/Metadata-File

---
name: $name           # Caution: DO NOT change the name.
description: Extension component for $name. Created using Rush.

version:
  number: auto        # Auto increments version number when built with '-r' ('--release') flag.
  name: $versionName

authors:
  - $author
${enableKt ? _getKtField() : ''}
assets:
  icon: icon.png      # Extension icon
  # other:              # Extension asset(s)
  #   - my_awesome_asset.anything

release:
  optimize: true

# Dependencies declared here should be present in the "deps" directory.
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
