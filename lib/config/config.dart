import 'dart:io';

import 'package:checked_yaml/checked_yaml.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:rush_cli/services/logger.dart';

part 'android.dart';
part 'kotlin.dart';

part 'config.g.dart';

@JsonSerializable(
    anyMap: true,
    checked: true,
    disallowUnrecognizedKeys: true,
    includeIfNull: false)
class Config {
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

  Config({
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
  factory Config._fromJson(Map json) => _$ConfigFromJson(json);

  static Future<Config?> load(File configFile, Logger lgr) async {
    lgr.dbg('Loading config from ${configFile.path}');
    try {
      return checkedYamlDecode(
          await configFile.readAsString(), (json) => Config._fromJson(json!));
    } catch (e) {
      lgr.err(e.toString());
    }
    return null;
  }
}
