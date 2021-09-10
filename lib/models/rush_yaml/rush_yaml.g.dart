// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rush_yaml.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RushYaml _$RushYamlFromJson(Map json) {
  return $checkedNew('RushYaml', json, () {
    $checkKeys(json, allowedKeys: const [
      'version',
      'homepage',
      'license',
      'assets',
      'authors',
      'deps',
      'android',
      'kotlin',
      'desugar'
    ], requiredKeys: const [
      'version'
    ]);
    final val = RushYaml(
      version: $checkedConvert(json, 'version', (v) => v as String),
      homepage: $checkedConvert(json, 'homepage', (v) => v as String?) ?? '',
      license: $checkedConvert(json, 'license', (v) => v as String?) ?? '',
      assets: $checkedConvert(json, 'assets',
              (v) => (v as List<dynamic>?)?.map((e) => e as String).toList()) ??
          [],
      authors: $checkedConvert(json, 'authors',
              (v) => (v as List<dynamic>?)?.map((e) => e as String).toList()) ??
          [],
      deps: $checkedConvert(
              json,
              'deps',
              (v) => (v as List<dynamic>?)
                  ?.map((e) =>
                      DepEntry.fromJson(Map<String, dynamic>.from(e as Map)))
                  .toList()) ??
          [],
      android: $checkedConvert(
          json,
          'android',
          (v) => v == null
              ? null
              : Android.fromJson(Map<String, dynamic>.from(v as Map))),
      kotlin: $checkedConvert(
          json,
          'kotlin',
          (v) => v == null
              ? null
              : Kotlin.fromJson(Map<String, dynamic>.from(v as Map))),
      desugar: $checkedConvert(
          json,
          'desugar',
          (v) => v == null
              ? null
              : Desugar.fromJson(Map<String, dynamic>.from(v as Map))),
    );
    return val;
  });
}

Map<String, dynamic> _$RushYamlToJson(RushYaml instance) => <String, dynamic>{
      'version': instance.version,
      'homepage': instance.homepage,
      'license': instance.license,
      'assets': instance.assets,
      'authors': instance.authors,
      'deps': instance.deps,
      'android': instance.android,
      'kotlin': instance.kotlin,
      'desugar': instance.desugar,
    };

Android _$AndroidFromJson(Map json) {
  return $checkedNew('Android', json, () {
    $checkKeys(json, allowedKeys: const ['compile_sdk', 'min_sdk']);
    final val = Android(
      compileSdk: $checkedConvert(json, 'compile_sdk', (v) => v as int?) ?? 31,
      minSdk: $checkedConvert(json, 'min_sdk', (v) => v as int?) ?? 7,
    );
    return val;
  }, fieldKeyMap: const {'compileSdk': 'compile_sdk', 'minSdk': 'min_sdk'});
}

Map<String, dynamic> _$AndroidToJson(Android instance) => <String, dynamic>{
      'compile_sdk': instance.compileSdk,
      'min_sdk': instance.minSdk,
    };

DepEntry _$DepEntryFromJson(Map json) {
  return $checkedNew('DepEntry', json, () {
    $checkKeys(json,
        allowedKeys: const ['compile_only', 'implement', 'exclude']);
    final val = DepEntry(
      implement: $checkedConvert(json, 'implement', (v) => v as String?),
      compileOnly: $checkedConvert(json, 'compile_only', (v) => v as String?),
      exclude: $checkedConvert(json, 'exclude',
          (v) => (v as List<dynamic>?)?.map((e) => e as String).toList()),
    );
    return val;
  }, fieldKeyMap: const {'compileOnly': 'compile_only'});
}

Map<String, dynamic> _$DepEntryToJson(DepEntry instance) => <String, dynamic>{
      'compile_only': instance.compileOnly,
      'implement': instance.implement,
      'exclude': instance.exclude,
    };

Desugar _$DesugarFromJson(Map json) {
  return $checkedNew('Desugar', json, () {
    $checkKeys(json,
        allowedKeys: const ['src_files', 'deps'],
        requiredKeys: const ['src_files']);
    final val = Desugar(
      srcFiles: $checkedConvert(json, 'src_files', (v) => v as bool),
      deps: $checkedConvert(json, 'deps', (v) => v as bool?) ?? false,
    );
    return val;
  }, fieldKeyMap: const {'srcFiles': 'src_files'});
}

Map<String, dynamic> _$DesugarToJson(Desugar instance) => <String, dynamic>{
      'src_files': instance.srcFiles,
      'deps': instance.deps,
    };

Kotlin _$KotlinFromJson(Map json) {
  return $checkedNew('Kotlin', json, () {
    $checkKeys(json,
        allowedKeys: const ['enable', 'version'],
        requiredKeys: const ['enable']);
    final val = Kotlin(
      enable: $checkedConvert(json, 'enable', (v) => v as bool),
      version: $checkedConvert(json, 'version', (v) => v as String?) ??
          'latest-stable',
    );
    return val;
  });
}

Map<String, dynamic> _$KotlinToJson(Kotlin instance) => <String, dynamic>{
      'enable': instance.enable,
      'version': instance.version,
    };
