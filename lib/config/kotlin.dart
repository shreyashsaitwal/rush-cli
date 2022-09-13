part of 'config.dart';

@JsonSerializable(
  anyMap: true,
  checked: true,
  disallowUnrecognizedKeys: true,
)
class Kotlin {
  @JsonKey(required: true, name: 'compiler_version', defaultValue: '1.7.10')
  final String compilerVersion;

  Kotlin({
    required this.compilerVersion,
  });

  factory Kotlin.fromJson(Map<String, dynamic> json) => _$KotlinFromJson(json);

  Map<String, dynamic> toJson() => _$KotlinToJson(this);
}
