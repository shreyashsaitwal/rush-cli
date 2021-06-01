import 'package:json_annotation/json_annotation.dart';

part 'release.g.dart';

@JsonSerializable(
  anyMap: true,
  checked: true,
  disallowUnrecognizedKeys: true,
)
class Release {
  @JsonKey(defaultValue: false)
  final bool optimize;

  Release({this.optimize = false});

  factory Release.fromJson(Map json) => _$ReleaseFromJson(json);

  Map<String, dynamic> toJson() => _$ReleaseToJson(this);
}
