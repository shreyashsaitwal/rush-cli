import 'package:json_annotation/json_annotation.dart';

part 'rush_lock.g.dart';

@JsonSerializable(
  anyMap: true,
  checked: true,
  disallowUnrecognizedKeys: true,
)
class RushLock {
  @JsonKey(name: 'resolved_deps')
  final List<ResolvedDep> resolvedDeps;

  RushLock({required this.resolvedDeps});

  factory RushLock.fromJson(Map<dynamic, dynamic> json) => _$RushLockFromJson(json);

  Map<String, dynamic> toJson() => _$RushLockToJson(this);
}

@JsonSerializable(
  anyMap: true,
  checked: true,
  disallowUnrecognizedKeys: true,
)
class ResolvedDep {
  @JsonKey(name: 'coord')
  final String coordinate;
  final String type;
  final String scope;
  @JsonKey(name: 'local_path')
  final String localPath;

  ResolvedDep({
    required this.coordinate,
    required this.type,
    required this.scope,
    required this.localPath,
  });

  factory ResolvedDep.fromJson(Map<String, dynamic> json) => _$ResolvedDepFromJson(json);

  Map<String, dynamic> toJson() => _$ResolvedDepToJson(this);
}
