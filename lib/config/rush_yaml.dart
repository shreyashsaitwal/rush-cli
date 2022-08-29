import 'dart:io';

import 'package:checked_yaml/checked_yaml.dart';
import 'package:json_annotation/json_annotation.dart';

part 'android.dart';
part 'kotlin.dart';

part 'rush_yaml.g.dart';

@JsonSerializable(
  anyMap: true,
  checked: true,
  disallowUnrecognizedKeys: true,
)
class RushYaml {
  @JsonKey(required: true)
  final String version;

  @JsonKey(name: 'dependencies')
  final List<String> runtimeDeps;

  @JsonKey(name: 'comptime_dependencies')
  final List<String> comptimeDeps;
  
  final String homepage;
  
  final String license;
  
  final bool desugar;
  
  final List<String> assets;
  
  final List<String> authors;
  
  final Android? android;
  
  final Kotlin? kotlin;

  RushYaml({
    required this.version,
    this.homepage = '',
    this.license = '',
    this.desugar = false,
    this.assets = const [],
    this.authors = const [],
    this.runtimeDeps = const [],
    this.comptimeDeps = const [],
    this.android,
    this.kotlin,
  });

  // ignore: strict_raw_type
  factory RushYaml._fromJson(Map json) => _$RushYamlFromJson(json);

  static Future<RushYaml> load(File configFile) async {
    try {
      return checkedYamlDecode(
          await configFile.readAsString(), (json) => RushYaml._fromJson(json!));
    } catch (e) {
      rethrow;
    }
  }
}
