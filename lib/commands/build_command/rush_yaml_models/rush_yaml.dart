import 'package:yaml/yaml.dart';

import 'assets.dart';
import 'kotlin.dart';
import 'release.dart';
import 'version.dart';

class RushYaml {
  String? name;
  String? description;
  List<String>? authors;
  Version? version;
  Assets? assets;
  Release? release;
  List<String>? deps;
  Kotlin? kotlin;
  String? license;
  int? minSdk;
  String? homepage;

  RushYaml({
    required this.name,
    required this.description,
    this.authors,
    this.version,
    this.assets,
    this.release,
    this.deps,
    this.kotlin,
    this.license,
    this.minSdk,
    this.homepage,
  });

  factory RushYaml.fromYaml(YamlMap yaml) {
    return RushYaml(
      name: yaml['name'] as String?,
      description: yaml['description'] as String?,
      authors: yaml['authors'] as List<String>?,
      version: yaml['version'] == null
          ? null
          : Version.fromYaml(yaml['version'] as YamlMap),
      assets: yaml['assets'] == null
          ? null
          : Assets.fromYaml(yaml['assets'] as YamlMap),
      release: yaml['release'] == null
          ? null
          : Release.fromYaml(yaml['release'] as YamlMap),
      deps: yaml['deps'] as List<String>?,
      kotlin: yaml['kotlin'] == null
          ? null
          : Kotlin.fromYaml(yaml['kotlin'] as YamlMap),
      license: yaml['license'] as String?,
      minSdk: yaml['min_sdk'] as int?,
      homepage: yaml['homepage'] as String?,
    );
  }
}
