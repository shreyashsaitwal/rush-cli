part of 'config.dart';

@JsonSerializable(
  anyMap: true,
  checked: true,
  disallowUnrecognizedKeys: true,
)
class Kotlin {
  @JsonKey(required: true, name: 'compiler_version', disallowNullValue: true)
  final String compilerVersion;

  const Kotlin({
    required this.compilerVersion,
  });

  factory Kotlin.fromJson(Map<String, dynamic> json) => _$KotlinFromJson(json);

  Map<String, dynamic> toJson() => _$KotlinToJson(this);
}
