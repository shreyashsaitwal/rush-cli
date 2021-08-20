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
      'build',
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
      version: $checkedConvert(json, 'version',
          (v) => Version.fromJson(Map<String, dynamic>.from(v as Map))),
      assets: $checkedConvert(json, 'assets',
          (v) => Assets.fromJson(Map<String, dynamic>.from(v as Map))),
      build: $checkedConvert(
          json,
          'build',
          (v) => v == null
              ? null
              : Build.fromJson(Map<String, dynamic>.from(v as Map))),
      authors: $checkedConvert(json, 'authors',
          (v) => (v as List<dynamic>?)?.map((e) => e as String).toList()),
      deps: $checkedConvert(
          json,
          'deps',
          (v) => (v as List<dynamic>?)
              ?.map((e) => Deps.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList()),
      license: $checkedConvert(json, 'license', (v) => v as String?),
      minSdk: $checkedConvert(json, 'min_sdk', (v) => v as int?),
      homepage: $checkedConvert(json, 'homepage', (v) => v as String?),
    );
    return val;
  }, fieldKeyMap: const {'minSdk': 'min_sdk'});
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

  writeNotNull('build', instance.build);
  writeNotNull('deps', instance.deps);
  writeNotNull('authors', instance.authors);
  writeNotNull('license', instance.license);
  writeNotNull('min_sdk', instance.minSdk);
  writeNotNull('homepage', instance.homepage);
  return val;
}

Assets _$AssetsFromJson(Map json) {
  return $checkedNew('Assets', json, () {
    $checkKeys(json,
        allowedKeys: const ['icon', 'other'], requiredKeys: const ['icon']);
    final val = Assets(
      icon: $checkedConvert(json, 'icon', (v) => v as String),
      other: $checkedConvert(json, 'other',
          (v) => (v as List<dynamic>?)?.map((e) => e as String).toList()),
    );
    return val;
  });
}

Map<String, dynamic> _$AssetsToJson(Assets instance) {
  final val = <String, dynamic>{
    'icon': instance.icon,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('other', instance.other);
  return val;
}

Build _$BuildFromJson(Map json) {
  return $checkedNew('Build', json, () {
    $checkKeys(json, allowedKeys: const ['desugar', 'kotlin', 'release']);
    final val = Build(
      $checkedConvert(
          json,
          'release',
          (v) => v == null
              ? null
              : Release.fromJson(Map<String, dynamic>.from(v as Map))),
      desugar: $checkedConvert(
          json,
          'desugar',
          (v) => v == null
              ? null
              : Desugar.fromJson(Map<String, dynamic>.from(v as Map))),
      kotlin: $checkedConvert(
          json,
          'kotlin',
          (v) => v == null
              ? null
              : Kotlin.fromJson(Map<String, dynamic>.from(v as Map))),
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

Deps _$DepsFromJson(Map json) {
  return $checkedNew('Deps', json, () {
    $checkKeys(json,
        allowedKeys: const ['compile_only', 'implement', 'exclude']);
    final val = Deps(
      implement: $checkedConvert(json, 'implement', (v) => v as String?),
      compileOnly: $checkedConvert(json, 'compile_only', (v) => v as String?),
      exclude: $checkedConvert(json, 'exclude',
          (v) => (v as List<dynamic>?)?.map((e) => e as String).toList()),
    );
    return val;
  }, fieldKeyMap: const {'compileOnly': 'compile_only'});
}

Map<String, dynamic> _$DepsToJson(Deps instance) => <String, dynamic>{
      'compile_only': instance.compileOnly,
      'implement': instance.implement,
      'exclude': instance.exclude,
    };

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
