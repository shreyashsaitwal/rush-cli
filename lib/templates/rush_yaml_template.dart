String getRushYaml(String name, String versionName, String author) {
  return '''
name: $name
description: Extension component for $name. Created using Rush.

version:
  number: auto
  name: $versionName

assets:
  icon: icon.png        # Extension icon
  # other:              # Extension asset(s)
  #   - my_awesome_pic.png

authors:
  - $author

# dependencies:
#   - my_awesome_library.[jar/aar]

''';
}
