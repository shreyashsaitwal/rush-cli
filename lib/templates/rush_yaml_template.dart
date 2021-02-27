String getRushYaml(String name, String versionName, String author) {
  return '''
name: $name           # Caution: DO NOT change the name.
description: Extension component for $name. Created using Rush.

version:
  number: auto        # Auto increments version number when built with '-r' (or '--release') flag.
  name: $versionName

assets:
  icon: icon.png      # Extension icon
  # other:              # Extension asset(s)
  #   - my_awesome_asset.anything

authors:
  - $author

# deps:         # Dependencies should be first added to the "deps" folder
#   - my_awesome_library.jar

''';
}
