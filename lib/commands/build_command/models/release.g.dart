// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'release.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Release _$ReleaseFromJson(Map json) {
  return $checkedNew('Release', json, () {
    $checkKeys(json, allowedKeys: const ['optimize']);
    final val = Release(
      optimize: $checkedConvert(json, 'optimize', (v) => v as bool?) ?? false,
    );
    return val;
  });
}

Map<String, dynamic> _$ReleaseToJson(Release instance) => <String, dynamic>{
      'optimize': instance.optimize,
    };
