import 'package:yaml/yaml.dart';

class Kotlin {
  bool? enable = false;

  Kotlin({this.enable});

  factory Kotlin.fromYaml(YamlMap yaml) {
    return Kotlin(
      enable: yaml['enable'] as bool?,
    );
  }
}
