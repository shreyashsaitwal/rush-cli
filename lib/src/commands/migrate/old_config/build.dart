part of 'old_config.dart';

@JsonSerializable(
  anyMap: true,
  checked: true,
  disallowUnrecognizedKeys: true,
)
class Build {
  @JsonKey(includeIfNull: false)
  final Desugar? desugar;

  @JsonKey(includeIfNull: false)
  final Kotlin? kotlin;

  @JsonKey(includeIfNull: false)
  final Release? release;

  Build(this.release, {this.desugar, this.kotlin});

  factory Build.fromJson(Map<String, dynamic> json) => _$BuildFromJson(json);

  Map<String, dynamic> toJson() => _$BuildToJson(this);
}

@JsonSerializable(
  anyMap: true,
  checked: true,
  disallowUnrecognizedKeys: true,
)
class Kotlin {
  @JsonKey(required: true)
  final bool enable;

  Kotlin({required this.enable});

  factory Kotlin.fromJson(Map<String, dynamic> json) => _$KotlinFromJson(json);

  Map<String, dynamic> toJson() => _$KotlinToJson(this);
}

@JsonSerializable(
  anyMap: true,
  checked: true,
  disallowUnrecognizedKeys: true,
)
class Desugar {
  @JsonKey(defaultValue: false, required: true)
  final bool enable;
  @JsonKey(defaultValue: false)
  // ignore: non_constant_identifier_names
  final bool? desugar_deps;

  // ignore: non_constant_identifier_names
  Desugar({required this.enable, this.desugar_deps});

  factory Desugar.fromJson(Map<String, dynamic> json) =>
      _$DesugarFromJson(json);

  Map<String, dynamic> toJson() => _$DesugarToJson(this);
}

@JsonSerializable(
  anyMap: true,
  checked: true,
  disallowUnrecognizedKeys: true,
)
class Release {
  @JsonKey(required: true)
  final bool optimize;

  Release({required this.optimize});

  factory Release.fromJson(Map<String, dynamic> json) =>
      _$ReleaseFromJson(json);

  Map<String, dynamic> toJson() => _$ReleaseToJson(this);
}
