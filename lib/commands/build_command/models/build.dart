import 'package:json_annotation/json_annotation.dart';

part 'build.g.dart';

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

  factory Build.fromJson(Map json) => _$BuildFromJson(json);

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

  factory Kotlin.fromJson(Map json) => _$KotlinFromJson(json);

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
  final bool? desugar_deps;

  Desugar({required this.enable, this.desugar_deps});

  factory Desugar.fromJson(Map json) => _$DesugarFromJson(json);

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

  factory Release.fromJson(Map json) => _$ReleaseFromJson(json);

  Map<String, dynamic> toJson() => _$ReleaseToJson(this);
}
