import 'package:json_annotation/json_annotation.dart';
import 'package:rush_prompt/rush_prompt.dart';

part 'assets.dart';
part 'build.dart';
part 'deps.dart';

part 'rush_yaml.g.dart';

@JsonSerializable(
  anyMap: true,
  checked: true,
  disallowUnrecognizedKeys: true,
)
class RushYaml {
  @JsonKey(required: true)
  String name;

  @JsonKey(required: true)
  String description;

  @JsonKey(required: true)
  Assets assets;

  @JsonKey(required: true)
  String version;

  @JsonKey(includeIfNull: false)
  Build? build;

  @JsonKey(includeIfNull: false)
  List<Deps>? deps;

  @JsonKey(includeIfNull: false)
  List<String>? authors;

  @JsonKey(includeIfNull: false)
  String? license;

  @JsonKey(includeIfNull: false, name: 'min_sdk')
  int? minSdk;

  @JsonKey(includeIfNull: false)
  String? homepage;

  RushYaml({
    required this.name,
    required this.description,
    required this.assets,
    required this.version,
    this.build,
    this.authors,
    this.deps,
    this.license,
    this.minSdk,
    this.homepage,
  });

  // Because `YamlMap` can't be casted to Map<String, dynamic>
  // ignore: strict_raw_type
  factory RushYaml.fromJson(Map json, BuildStep step) =>
      _$RushYamlFromJson(json);

  Map<String, dynamic> toJson() => _$RushYamlToJson(this);
}
