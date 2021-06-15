// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'build.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Build _$BuildFromJson(Map json) {
  return $checkedNew('Build', json, () {
    $checkKeys(json, allowedKeys: const ['desugar', 'kotlin', 'release']);
    final val = Build(
      $checkedConvert(json, 'release',
          (v) => v == null ? null : Release.fromJson(v as Map)),
      desugar: $checkedConvert(json, 'desugar',
          (v) => v == null ? null : Desugar.fromJson(v as Map)),
      kotlin: $checkedConvert(
          json, 'kotlin', (v) => v == null ? null : Kotlin.fromJson(v as Map)),
    );
    return val;
  });
}

Map<String, dynamic> _$BuildToJson(Build instance) {
  final val = <String, dynamic>{};

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('desugar', instance.desugar);
  writeNotNull('kotlin', instance.kotlin);
  writeNotNull('release', instance.release);
  return val;
}

Kotlin _$KotlinFromJson(Map json) {
  return $checkedNew('Kotlin', json, () {
    $checkKeys(json,
        allowedKeys: const ['enable'], requiredKeys: const ['enable']);
    final val = Kotlin(
      enable: $checkedConvert(json, 'enable', (v) => v as bool),
    );
    return val;
  });
}

Map<String, dynamic> _$KotlinToJson(Kotlin instance) => <String, dynamic>{
      'enable': instance.enable,
    };

Desugar _$DesugarFromJson(Map json) {
  return $checkedNew('Desugar', json, () {
    $checkKeys(json,
        allowedKeys: const ['enable', 'desugar_deps'],
        requiredKeys: const ['enable']);
    final val = Desugar(
      enable: $checkedConvert(json, 'enable', (v) => v as bool?) ?? false,
      desugar_deps:
          $checkedConvert(json, 'desugar_deps', (v) => v as bool?) ?? false,
    );
    return val;
  });
}

Map<String, dynamic> _$DesugarToJson(Desugar instance) => <String, dynamic>{
      'enable': instance.enable,
      'desugar_deps': instance.desugar_deps,
    };

Release _$ReleaseFromJson(Map json) {
  return $checkedNew('Release', json, () {
    $checkKeys(json,
        allowedKeys: const ['optimize'], requiredKeys: const ['optimize']);
    final val = Release(
      optimize: $checkedConvert(json, 'optimize', (v) => v as bool),
    );
    return val;
  });
}

Map<String, dynamic> _$ReleaseToJson(Release instance) => <String, dynamic>{
      'optimize': instance.optimize,
    };
