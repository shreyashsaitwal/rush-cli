import 'dart:io';

import 'package:checked_yaml/checked_yaml.dart';
import 'package:collection/collection.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:rush/src/config/library_placement.dart';
import 'package:rush/src/services/logger.dart';
import 'package:rush/src/utils/constants.dart';
import 'package:rush/src/utils/error_message.dart';

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

  @JsonKey(disallowNullValue: true)
  final Map<String, LibraryPlacement> libraries;

  @JsonKey(name: 'min_sdk', disallowNullValue: true)
  final int minSdk;

  @JsonKey(disallowNullValue: true)
  final List<String> repositories;

  @JsonKey(disallowNullValue: true)
  final String homepage;

  @JsonKey(disallowNullValue: true)
  final String license;

  @JsonKey(disallowNullValue: true)
  final bool? desugar;

  @JsonKey(disallowNullValue: true)
  final List<String> assets;

  @JsonKey(disallowNullValue: true)
  final List<String>? authors;

  @JsonKey(disallowNullValue: true)
  final Kotlin kotlin;

  Config({
    required this.version,
    this.minSdk = 7,
    this.homepage = '',
    this.license = '',
    this.desugar,
    this.assets = const [],
    this.authors,
    this.dependencies = const [],
    this.providedDependencies = const [],
    this.libraries = const {},
    this.repositories = const [],
    this.kotlin = const Kotlin(compilerVersion: defaultKtVersion),
  });

  // ignore: strict_raw_type
  factory Config._fromJson(Map json) =>
      _$ConfigFromJson(json).._checkLibraries(json);

  Map<String, dynamic> toJson() => _$ConfigToJson(this);

  Set<String> get excludedLibraries => {
        for (final MapEntry(key: library, value: placement)
            in libraries.entries)
          if (placement == LibraryPlacement.exclude) library,
      };

  // ignore: strict_raw_type
  void _checkLibraries(Map json) {
    final excludedDependency = excludedLibraries
        .firstWhereOrNull(dependencies.map(libraryKey).toSet().contains);
    if (excludedDependency != null) {
      throw CheckedFromJsonException(json, 'libraries', 'Config',
          '$excludedDependency is in dependencies, so it can\'t be excluded. Remove it from dependencies instead.');
    }
  }

  List<String> get ignoredKeys => [
        if (authors != null) 'authors',
        if (desugar != null) 'desugar',
      ];

  static Future<Config?> require(File configFile, Logger lgr) {
    if (!configFile.existsSync()) {
      lgr.err(
          'No rush.yml found in ${configFile.parent.path}. Run this command inside a Rush project, '
          'or create one with `rush create`.');
    }
    return load(configFile, lgr);
  }

  static Future<Config?> load(File configFile, Logger lgr) async {
    if (configFile.existsSync()) {
      try {
        return checkedYamlDecode<Config>(
            await configFile.readAsString(), (json) => Config._fromJson(json!),
            sourceUrl: Uri.file('rush.yml'));
      } on ParsedYamlException catch (e) {
        lgr.err(e.formattedMessage ?? e.message);
      } catch (e) {
        lgr.err(errorMessage(e));
      }
    }
    return null;
  }
}
