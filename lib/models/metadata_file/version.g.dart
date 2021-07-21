// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'version.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Version _$VersionFromJson(Map json) {
  return $checkedNew('Version', json, () {
    $checkKeys(json,
        allowedKeys: const ['number', 'name'], requiredKeys: const ['number']);
    final val = Version(
      number: $checkedConvert(json, 'number', (v) => v),
      name: $checkedConvert(json, 'name', (v) => v),
    );
    return val;
  });
}

Map<String, dynamic> _$VersionToJson(Version instance) => <String, dynamic>{
      'number': instance.number,
      'name': instance.name,
    };
