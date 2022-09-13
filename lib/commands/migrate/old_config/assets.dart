part of 'old_config.dart';

@JsonSerializable(
  anyMap: true,
  checked: true,
  disallowUnrecognizedKeys: true,
)
class Assets {
  @JsonKey(required: true)
  final String icon;

  @JsonKey(includeIfNull: false)
  final List<String>? other;

  Assets({required this.icon, this.other});

  factory Assets.fromJson(Map<String, dynamic> json) => _$AssetsFromJson(json);

  Map<String, dynamic> toJson() => _$AssetsToJson(this);
}
