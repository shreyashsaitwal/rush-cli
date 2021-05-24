import 'package:yaml/yaml.dart';

class Version {
  String? number;
  String? name;

  Version({this.number, this.name});

  factory Version.fromYaml(YamlMap yaml) {
    return Version(
      number: yaml['number'] as String?,
      name: yaml['name'] as String?,
    );
  }
}
