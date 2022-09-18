part of 'config.dart';

@JsonSerializable(
  anyMap: true,
  checked: true,
  disallowUnrecognizedKeys: true,
)
class Android {
  @JsonKey(defaultValue: 31, name: 'compile_sdk')
  final int? compileSdk;

  @JsonKey(defaultValue: 7, name: 'min_sdk')
  final int? minSdk;

  Android({
    this.compileSdk,
    this.minSdk,
  });

  factory Android.fromJson(Map<String, dynamic> json) =>
      _$AndroidFromJson(json);

  Map<String, dynamic> toJson() => _$AndroidToJson(this);
}
