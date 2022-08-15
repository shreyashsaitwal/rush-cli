part of 'rush_yaml.dart';

@JsonSerializable(
  anyMap: true,
  checked: true,
  disallowUnrecognizedKeys: true,
)
class Kotlin {
  @JsonKey(required: true)
  final bool enable;

  @JsonKey(defaultValue: 'latest-stable')
  final String? version;

  Kotlin({
    required this.enable,
    this.version,
  });

  factory Kotlin.fromJson(Map<String, dynamic> json) => _$KotlinFromJson(json);

  Map<String, dynamic> toJson() => _$KotlinToJson(this);
}
