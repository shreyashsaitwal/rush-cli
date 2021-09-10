// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rush_lock.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RushLock _$RushLockFromJson(Map json) {
  return $checkedNew('RushLock', json, () {
    $checkKeys(json,
        allowedKeys: const ['resolved_artifacts', 'skipped_artifacts']);
    final val = RushLock(
      resolvedArtifacts: $checkedConvert(
          json,
          'resolved_artifacts',
          (v) => (v as List<dynamic>)
              .map((e) => ResolvedArtifact.fromJson(
                  Map<String, dynamic>.from(e as Map)))
              .toList()),
      skippedArtifacts: $checkedConvert(
          json,
          'skipped_artifacts',
          (v) => (v as List<dynamic>)
              .map((e) =>
                  SkippedArtifact.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList()),
    );
    return val;
  }, fieldKeyMap: const {
    'resolvedArtifacts': 'resolved_artifacts',
    'skippedArtifacts': 'skipped_artifacts'
  });
}

Map<String, dynamic> _$RushLockToJson(RushLock instance) => <String, dynamic>{
      'resolved_artifacts': instance.resolvedArtifacts,
      'skipped_artifacts': instance.skippedArtifacts,
    };

ResolvedArtifact _$ResolvedArtifactFromJson(Map json) {
  return $checkedNew('ResolvedArtifact', json, () {
    $checkKeys(json, allowedKeys: const [
      'coord',
      'type',
      'scope',
      'direct',
      'path',
      'deps'
    ]);
    final val = ResolvedArtifact(
      coordinate: $checkedConvert(json, 'coord', (v) => v as String),
      type: $checkedConvert(json, 'type', (v) => v as String),
      scope: $checkedConvert(json, 'scope', (v) => v as String),
      isDirect: $checkedConvert(json, 'direct', (v) => v as bool),
      path: $checkedConvert(json, 'path', (v) => v as String),
      deps: $checkedConvert(json, 'deps',
          (v) => (v as List<dynamic>).map((e) => e as String).toList()),
    );
    return val;
  }, fieldKeyMap: const {'coordinate': 'coord', 'isDirect': 'direct'});
}

Map<String, dynamic> _$ResolvedArtifactToJson(ResolvedArtifact instance) =>
    <String, dynamic>{
      'coord': instance.coordinate,
      'type': instance.type,
      'scope': instance.scope,
      'direct': instance.isDirect,
      'path': instance.path,
      'deps': instance.deps,
    };

SkippedArtifact _$SkippedArtifactFromJson(Map json) {
  return $checkedNew('SkippedArtifact', json, () {
    $checkKeys(json,
        allowedKeys: const ['coord', 'available_version', 'scope']);
    final val = SkippedArtifact(
      coordinate: $checkedConvert(json, 'coord', (v) => v as String),
      availableVer:
          $checkedConvert(json, 'available_version', (v) => v as String),
      scope: $checkedConvert(json, 'scope', (v) => v as String),
    );
    return val;
  }, fieldKeyMap: const {
    'coordinate': 'coord',
    'availableVer': 'available_version'
  });
}

Map<String, dynamic> _$SkippedArtifactToJson(SkippedArtifact instance) =>
    <String, dynamic>{
      'coord': instance.coordinate,
      'available_version': instance.availableVer,
      'scope': instance.scope,
    };
