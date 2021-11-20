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
      'build',
      'deps',
      'repos',
      'authors',
      'license_url',
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
      version: $checkedConvert(json, 'version',
          (v) => Version.fromJson(Map<String, dynamic>.from(v as Map))),
      assets: $checkedConvert(json, 'assets',
          (v) => Assets.fromJson(Map<String, dynamic>.from(v as Map))),
      release: $checkedConvert(
          json,
          'release',
          (v) => v == null
              ? null
              : Release.fromJson(Map<String, dynamic>.from(v as Map))),
      build: $checkedConvert(
          json,
          'build',
          (v) => v == null
              ? null
              : Build.fromJson(Map<String, dynamic>.from(v as Map))),
      authors: $checkedConvert(json, 'authors',
          (v) => (v as List<dynamic>?)?.map((e) => e as String).toList()),
      deps: $checkedConvert(json, 'deps',
          (v) => (v as List<dynamic>?)?.map((e) => e as String).toList()),
      repos: $checkedConvert(json, 'repos',
          (v) => (v as List<dynamic>?)?.map((e) => e as String).toList()),
      license: $checkedConvert(json, 'license', (v) => v as String?),
      min_sdk: $checkedConvert(json, 'min_sdk', (v) => v as int?),
      homepage: $checkedConvert(json, 'homepage', (v) => v as String?),
    );
    $checkedConvert(json, 'license_url', (v) => val.license_url = v as String?);
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
  writeNotNull('build', instance.build);
  writeNotNull('deps', instance.deps);
  writeNotNull('repos', instance.repos);
  writeNotNull('authors', instance.authors);
  writeNotNull('license_url', instance.license_url);
  writeNotNull('license', instance.license);
  writeNotNull('min_sdk', instance.min_sdk);
  writeNotNull('homepage', instance.homepage);
  return val;
}
