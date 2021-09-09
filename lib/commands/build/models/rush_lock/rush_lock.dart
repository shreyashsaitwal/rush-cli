import 'package:json_annotation/json_annotation.dart';

part 'rush_lock.g.dart';

@JsonSerializable(
  anyMap: true,
  checked: true,
  disallowUnrecognizedKeys: true,
)
class RushLock {
  @JsonKey(name: 'resolved_artifacts')
  final List<ResolvedArtifact> resolvedArtifacts;

  @JsonKey(name: 'skipped_artifacts')
  final List<SkippedArtifact> skippedArtifacts;

  RushLock({required this.resolvedArtifacts, required this.skippedArtifacts});

  factory RushLock.fromJson(Map<dynamic, dynamic> json) =>
      _$RushLockFromJson(json);

  Map<String, dynamic> toJson() => _$RushLockToJson(this);
}

@JsonSerializable(
  anyMap: true,
  checked: true,
  disallowUnrecognizedKeys: true,
)
class ResolvedArtifact {
  @JsonKey(name: 'coord')
  final String coordinate;
  final String type;
  final String scope;
  final String path;

  ResolvedArtifact({
    required this.coordinate,
    required this.type,
    required this.scope,
    required this.path,
  });

  factory ResolvedArtifact.fromJson(Map<String, dynamic> json) =>
      _$ResolvedArtifactFromJson(json);

  Map<String, dynamic> toJson() => _$ResolvedArtifactToJson(this);
}

@JsonSerializable(
  anyMap: true,
  checked: true,
  disallowUnrecognizedKeys: true,
)
class SkippedArtifact {
  @JsonKey(name: 'coord')
  final String coordinate;

  @JsonKey(name: 'available_version')
  final String availableVer;

  final String scope;

  SkippedArtifact({
    required this.coordinate,
    required this.availableVer,
    required this.scope,
  });

  factory SkippedArtifact.fromJson(Map<String, dynamic> json) =>
      _$SkippedArtifactFromJson(json);

  Map<String, dynamic> toJson() => _$SkippedArtifactToJson(this);
}
