// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'kotlin.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Kotlin _$KotlinFromJson(Map json) {
  return $checkedNew('Kotlin', json, () {
    $checkKeys(json, allowedKeys: const ['enable']);
    final val = Kotlin(
      enable: $checkedConvert(json, 'enable', (v) => v as bool?) ?? false,
    );
    return val;
  });
}

Map<String, dynamic> _$KotlinToJson(Kotlin instance) => <String, dynamic>{
      'enable': instance.enable,
    };
