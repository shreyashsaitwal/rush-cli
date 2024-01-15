import 'dart:io';

import 'package:checked_yaml/checked_yaml.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:rush_cli/src/services/logger.dart';
import 'package:rush_cli/src/utils/constants.dart';

part 'android.dart';

part 'kotlin.dart';

part 'config.g.dart';

@JsonSerializable(
  anyMap: true,
  checked: true,
  disallowUnrecognizedKeys: true,
  includeIfNull: false,
)
class Config {
  @JsonKey(required: true)
  final String version;

  @JsonKey(disallowNullValue: true)
  final List<String> dependencies;

  @JsonKey(name: 'provided_dependencies', disallowNullValue: true)
  final List<String> providedDependencies;

  @JsonKey(name: 'min_sdk', disallowNullValue: true)
  final int minSdk;

  @JsonKey(disallowNullValue: true)
  final List<String> repositories;

  @JsonKey(disallowNullValue: true)
  final String homepage;

  @JsonKey(disallowNullValue: true)
  final String license;

  @JsonKey(disallowNullValue: true)
  final bool desugar;

  @JsonKey(disallowNullValue: true)
  final List<String> assets;

  @JsonKey(disallowNullValue: true)
  final List<String> authors;

  @JsonKey(disallowNullValue: true)
  final Kotlin kotlin;

  Config({
    required this.version,
    this.minSdk = 7,
    this.homepage = '',
    this.license = '',
    this.desugar = false,
    this.assets = const [],
    this.authors = const [],
    this.dependencies = const [],
    this.providedDependencies = const [],
    this.repositories = const [],
    this.kotlin = const Kotlin(compilerVersion: defaultKtVersion),
  });

  // ignore: strict_raw_type
  factory Config._fromJson(Map json) => _$ConfigFromJson(json);

  static Future<Config?> load(File configFile, Logger lgr) async {
    if (configFile.existsSync()) {
      try {
        return checkedYamlDecode(
            await configFile.readAsString(), (json) => Config._fromJson(json!));
      } catch (e) {
        lgr.err(e.toString());
      }
    }
    return null;
  }
}
