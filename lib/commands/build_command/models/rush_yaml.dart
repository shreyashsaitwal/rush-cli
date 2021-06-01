import 'package:json_annotation/json_annotation.dart';

import 'assets.dart';
import 'kotlin.dart';
import 'release.dart';
import 'version.dart';

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
  Version version;

  @JsonKey(required: true)
  Assets assets;

  @JsonKey(includeIfNull: false)
  Release? release;

  @JsonKey(includeIfNull: false)
  Kotlin? kotlin;

  @JsonKey(includeIfNull: false)
  List<String>? deps;

  @JsonKey(includeIfNull: false)
  List<String>? authors;

  @JsonKey(includeIfNull: false)
  String? license;

  @JsonKey(includeIfNull: false)
  int? min_sdk;

  @JsonKey(includeIfNull: false)
  String? homepage;

  RushYaml({
    required this.name,
    required this.description,
    required this.version,
    required this.assets,
    this.release,
    this.kotlin,
    this.authors,
    this.deps,
    this.license,
    this.min_sdk,
    this.homepage,
  });

  factory RushYaml.fromJson(Map json) => _$RushYamlFromJson(json);

  Map<String, dynamic> toJson() => _$RushYamlToJson(this);
}
