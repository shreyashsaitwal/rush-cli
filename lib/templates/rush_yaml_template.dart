String getRushYaml(String name, String versionName, String author) {
  return '''
name: $name
description: Extension component for $name. Created using Rush.

version:
  number: auto          # Auto increaments version number when built with '-r' (or '--release') flag.
  name: $versionName

# Doesn't work
# assets:
  # icon: icon.png      # Extension icon
  # other:              # Extension asset(s)
  #   - my_awesome_pic.png

authors:
  - $author

# Untested
# dependencies:
#   - my_awesome_library.jar

''';
}
