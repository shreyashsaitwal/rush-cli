import 'package:json_annotation/json_annotation.dart';

part 'release.g.dart';

@JsonSerializable(
  anyMap: true,
  checked: true,
  disallowUnrecognizedKeys: true,
)
class Release {
  @JsonKey(required: true)
  final bool optimize;

  Release({required this.optimize});

  factory Release.fromJson(Map json) => _$ReleaseFromJson(json);

  Map<String, dynamic> toJson() => _$ReleaseToJson(this);
}
