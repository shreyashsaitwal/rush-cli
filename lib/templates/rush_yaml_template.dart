String generateRushYaml(String name, String versionName, String author) {
  return '''
name: $name
description: Extension component for $name. Created using Rush.

version:
  number: auto
  name: $versionName

# min_sdk: 14

assets:
  icon: icon.png        # Extension icon
  # other:              # Extension asset(s)
  #   - my_awesome_pic.png

authors:
  - $author

# dependencies:
#   - json:
#       group: org.json
#       version: latest

''';
}
