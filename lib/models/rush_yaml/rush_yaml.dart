import 'package:json_annotation/json_annotation.dart';

part 'android.dart';
part 'dep_entry.dart';
part 'desugar.dart';
part 'kotlin.dart';

part 'rush_yaml.g.dart';

@JsonSerializable(
  anyMap: true,
  checked: true,
  disallowUnrecognizedKeys: true,
)
class RushYaml {
  @JsonKey(required: true)
  final String version;

  @JsonKey(defaultValue: '')
  final String? homepage;

  @JsonKey(defaultValue: '')
  final String? license;

  @JsonKey(defaultValue: [])
  final List<String>? assets;

  @JsonKey(defaultValue: [])
  final List<String>? authors;

  @JsonKey(defaultValue: [])
  final List<DepEntry>? deps;

  final Android? android;
  final Kotlin? kotlin;
  final Desugar? desugar;

  RushYaml({
    required this.version,
    this.homepage,
    this.license,
    this.assets,
    this.authors,
    this.deps,
    this.android,
    this.kotlin,
    this.desugar,
  });

  // ignore: strict_raw_type
  factory RushYaml.fromJson(Map json) => _$RushYamlFromJson(json);

  Map<String, dynamic> toJson() => _$RushYamlToJson(this);
}
