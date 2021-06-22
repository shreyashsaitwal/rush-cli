import 'package:json_annotation/json_annotation.dart';
import 'package:rush_cli/commands/build_command/models/assets.dart';
import 'package:rush_cli/commands/build_command/models/build.dart' show Build;
import 'package:rush_cli/commands/build_command/models/release.dart';
import 'package:rush_cli/commands/build_command/models/version.dart';
import 'package:rush_prompt/rush_prompt.dart';

part 'rush_yaml.g.dart';

@JsonSerializable(
  anyMap: true,
  checked: true,
  disallowUnrecognizedKeys: true,
)
class RushYaml {
  @JsonKey(required: true)
  String name;

  @JsonKey(required: true)
  String description;

  @JsonKey(required: true)
  Version version;

  @JsonKey(required: true)
  Assets assets;

  @JsonKey(includeIfNull: false)
  Release? release;

  @JsonKey(includeIfNull: false)
  Build? build;

  @JsonKey(includeIfNull: false)
  List<String>? deps;

  @JsonKey(includeIfNull: false)
  List<String>? authors;

  @JsonKey(defaultValue: null, includeIfNull: false)
  // ignore: non_constant_identifier_names
  String? license_url;

  @JsonKey(includeIfNull: false)
  String? license;

  @JsonKey(includeIfNull: false)
  // ignore: non_constant_identifier_names
  int? min_sdk;

  @JsonKey(includeIfNull: false)
  String? homepage;

  RushYaml({
    required this.name,
    required this.description,
    required this.version,
    required this.assets,
    this.release,
    this.build,
    this.authors,
    this.deps,
    this.license,
    // ignore: non_constant_identifier_names
    this.min_sdk,
    this.homepage,
  });

  // Because `YamlMap` can't be casted to Map<String, dynamic>
  // ignore: strict_raw_type
  factory RushYaml.fromJson(Map json, BuildStep step) {
    final yaml = _$RushYamlFromJson(json);

    if (yaml.license_url != null) {
      _printLicWarn(step, yaml.license_url!);
    }
    if (yaml.release != null) {
      _printReleaseWarn(step);
    }

    return yaml;
  }

  Map<String, dynamic> toJson() => _$RushYamlToJson(this);

  static void _printLicWarn(BuildStep step, String value) {
    final brightBlack = '\u001b[30;1m';
    final cyan = '\u001b[36m';
    final green = '\u001b[32m';
    final reset = '\u001b[0m';

    step.log(LogType.warn,
        'Field `license_url` is deprecated. Consider using field `license` instead.');
    step.log(LogType.warn, ' ' * 4 + '$brightBlack|$reset', addPrefix: false);
    step.log(LogType.warn,
        ' ' * 4 + '$brightBlack|$reset${cyan}license: $green\'$value\'$reset',
        addPrefix: false);
    step.log(LogType.warn, ' ' * 4 + '$brightBlack|$reset', addPrefix: false);
  }

  static void _printReleaseWarn(BuildStep step) {
    final brightBlack = '\u001b[30;1m';
    final cyan = '\u001b[36m';
    final green = '\u001b[32m';
    final reset = '\u001b[0m';

    step.log(LogType.warn,
        'Field `release` is deprecated. Consider using field `build.release` instead.');
    step.log(LogType.warn, ' ' * 4 + '$brightBlack|$reset', addPrefix: false);
    step.log(LogType.warn, ' ' * 4 + '$brightBlack|$reset${cyan}build:',
        addPrefix: false);
    step.log(LogType.warn, ' ' * 4 + '$brightBlack|$reset$cyan  release:',
        addPrefix: false);
    step.log(LogType.warn,
        ' ' * 4 + '$brightBlack|$reset$cyan    optimize: ${green}true',
        addPrefix: false);
    step.log(LogType.warn, ' ' * 4 + '$brightBlack|$reset', addPrefix: false);
  }
}
