import 'package:yaml/yaml.dart';

class Assets {
  String? icon;
  List<String>? other;

  Assets({this.icon, this.other});

  factory Assets.fromYaml(YamlMap yaml) {
    return Assets(
      icon: yaml['icon'] as String?,
      other: yaml['other'] as List<String>?,
    );
  }
}
