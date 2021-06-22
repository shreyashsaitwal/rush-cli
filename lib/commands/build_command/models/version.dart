import 'package:json_annotation/json_annotation.dart';

part 'version.g.dart';

@JsonSerializable(
  anyMap: true,
  checked: true,
  disallowUnrecognizedKeys: true,
)
class Version {
  @JsonKey(required: true)
  final dynamic number;
  final String? name;

  const Version({required this.number, this.name});

  factory Version.fromJson(Map<String, dynamic> json) => _$VersionFromJson(json);

  Map<String, dynamic> toJson() => _$VersionToJson(this);
}
