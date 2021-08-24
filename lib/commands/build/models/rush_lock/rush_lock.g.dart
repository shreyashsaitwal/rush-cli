// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rush_lock.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RushLock _$RushLockFromJson(Map json) {
  return $checkedNew('RushLock', json, () {
    $checkKeys(json, allowedKeys: const ['resolved_deps']);
    final val = RushLock(
      resolvedDeps: $checkedConvert(
          json,
          'resolved_deps',
          (v) => (v as List<dynamic>)
              .map((e) =>
                  ResolvedDep.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList()),
    );
    return val;
  }, fieldKeyMap: const {'resolvedDeps': 'resolved_deps'});
}

Map<String, dynamic> _$RushLockToJson(RushLock instance) => <String, dynamic>{
      'resolved_deps': instance.resolvedDeps,
    };

ResolvedDep _$ResolvedDepFromJson(Map json) {
  return $checkedNew('ResolvedDep', json, () {
    $checkKeys(json,
        allowedKeys: const ['coord', 'type', 'scope', 'local_path']);
    final val = ResolvedDep(
      coordinate: $checkedConvert(json, 'coord', (v) => v as String),
      type: $checkedConvert(json, 'type', (v) => v as String),
      scope: $checkedConvert(json, 'scope', (v) => v as String),
      localPath: $checkedConvert(json, 'local_path', (v) => v as String),
    );
    return val;
  }, fieldKeyMap: const {'coordinate': 'coord', 'localPath': 'local_path'});
}

Map<String, dynamic> _$ResolvedDepToJson(ResolvedDep instance) =>
    <String, dynamic>{
      'coord': instance.coordinate,
      'type': instance.type,
      'scope': instance.scope,
      'local_path': instance.localPath,
    };
