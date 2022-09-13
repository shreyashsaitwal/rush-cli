import 'dart:io';

import 'package:checked_yaml/checked_yaml.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:rush_cli/services/logger.dart';
import 'package:tint/tint.dart';

part 'assets.dart';
part 'build.dart';
part 'version.dart';
part 'old_config.g.dart';

@JsonSerializable(
  anyMap: true,
  checked: true,
  disallowUnrecognizedKeys: true,
  includeIfNull: false,
)
class OldConfig {
  @JsonKey(required: true)
  String name;

  @JsonKey(required: true)
  String description;

  @JsonKey(required: true)
  Version version;

  @JsonKey(required: true)
  Assets assets;

  Release? release;

  Build? build;

  List<String>? deps;

  List<String>? authors;

  @JsonKey(defaultValue: null, name: 'license_url')
  String? licenseUrl;

  String? license;

  @JsonKey(name: 'min_sdk')
  int? minSdk;

  String? homepage;

  OldConfig({
    required this.name,
    required this.description,
    required this.version,
    required this.assets,
    this.release,
    this.build,
    this.authors,
    this.deps,
    this.license,
    this.minSdk,
    this.homepage,
  });

  factory OldConfig._fromJson(Map json) => _$OldConfigFromJson(json);

  static Future<OldConfig?> load(File configFile, Logger lgr) async {
    lgr.dbg('Loading config from ${configFile.path}');
    try {
      return checkedYamlDecode(await configFile.readAsString(),
          (json) => OldConfig._fromJson(json!));
    } catch (e) {
      lgr.err(e.toString());
      lgr.log(
          'Are you sure you are inside a Rush project created prior to v2.0.0?',
          'help '.green());
    }
    return null;
  }
}
