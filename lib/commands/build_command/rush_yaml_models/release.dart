import 'package:yaml/yaml.dart';

class Release {
  bool? optimize = false;

  Release({this.optimize});

  factory Release.fromYaml(YamlMap yaml) {
    return Release(
      optimize: yaml['optimize'] as bool?,
    );
  }
}
