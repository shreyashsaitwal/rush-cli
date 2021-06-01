import 'package:json_annotation/json_annotation.dart';

part 'kotlin.g.dart';

@JsonSerializable(
  anyMap: true,
  checked: true,
  disallowUnrecognizedKeys: true,
)
class Kotlin {
  @JsonKey(defaultValue: false)
  final bool enable;

  Kotlin({this.enable = false});

  factory Kotlin.fromJson(Map json) => _$KotlinFromJson(json);

  Map<String, dynamic> toJson() => _$KotlinToJson(this);
}
