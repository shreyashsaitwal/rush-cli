part of 'rush_yaml.dart';

@JsonSerializable(
  anyMap: true,
  checked: true,
  disallowUnrecognizedKeys: true,
)
class Desugar {
  @JsonKey(required: true, name: 'src_files')
  final bool srcFiles;

  @JsonKey(defaultValue: false)
  final bool? deps;

  Desugar({
    required this.srcFiles,
    this.deps,
  });

  factory Desugar.fromJson(Map<String, dynamic> json) =>
      _$DesugarFromJson(json);

  Map<String, dynamic> toJson() => _$DesugarToJson(this);
}
