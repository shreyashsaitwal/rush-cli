// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rush_yaml.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RushYaml _$RushYamlFromJson(Map json) {
  return $checkedNew('RushYaml', json, () {
    $checkKeys(json, allowedKeys: const [
      'name',
      'description',
      'version',
      'assets',
      'release',
      'kotlin',
      'deps',
      'authors',
      'license',
      'min_sdk',
      'homepage'
    ], requiredKeys: const [
      'name',
      'description',
      'version',
      'assets'
    ]);
    final val = RushYaml(
      name: $checkedConvert(json, 'name', (v) => v as String),
      description: $checkedConvert(json, 'description', (v) => v as String),
      version:
          $checkedConvert(json, 'version', (v) => Version.fromJson(v as Map)),
      assets: $checkedConvert(json, 'assets', (v) => Assets.fromJson(v as Map)),
      release: $checkedConvert(json, 'release',
          (v) => v == null ? null : Release.fromJson(v as Map)),
      kotlin: $checkedConvert(
          json, 'kotlin', (v) => v == null ? null : Kotlin.fromJson(v as Map)),
      authors: $checkedConvert(json, 'authors',
          (v) => (v as List<dynamic>?)?.map((e) => e as String).toList()),
      deps: $checkedConvert(json, 'deps',
          (v) => (v as List<dynamic>?)?.map((e) => e as String).toList()),
      license: $checkedConvert(json, 'license', (v) => v as String?),
      min_sdk: $checkedConvert(json, 'min_sdk', (v) => v as int?),
      homepage: $checkedConvert(json, 'homepage', (v) => v as String?),
    );
    return val;
  });
}

Map<String, dynamic> _$RushYamlToJson(RushYaml instance) {
  final val = <String, dynamic>{
    'name': instance.name,
    'description': instance.description,
    'version': instance.version,
    'assets': instance.assets,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('release', instance.release);
  writeNotNull('kotlin', instance.kotlin);
  writeNotNull('deps', instance.deps);
  writeNotNull('authors', instance.authors);
  writeNotNull('license', instance.license);
  writeNotNull('min_sdk', instance.min_sdk);
  writeNotNull('homepage', instance.homepage);
  return val;
}
