import 'dart:io' show File, exit;

import 'package:rush_cli/helpers/utils.dart';
import 'package:rush_prompt/rush_prompt.dart';
import 'package:yaml/yaml.dart';

/// Mixin to check if the rush.yaml file is valid.
class CheckRushYml {
  static void check(File rushYml, BuildStep step) {
    final YamlMap yaml = loadYaml(rushYml.readAsStringSync());
    var isInvalid = false;

    if (!yaml.containsKey('name') && (yaml['name'] as String).isEmpty) {
      step
        ..logErr('Field \'name\' doesn\'t exist or is empty in rush.yml',
            addSpace: true)
        ..finishNotOk('Failed');
      isInvalid = true;
    }

    if (!yaml.containsKey('description') &&
        (yaml['description'] as String).isEmpty) {
      step
        ..logErr('Field \'description\' doesn\'t exist or is empty in rush.yml',
            addSpace: true)
        ..finishNotOk('Failed');
      isInvalid = true;
    }

    if (yaml['assets']['icon'] == null ||
        (yaml['assets']['icon'] as String).isEmpty) {
      step
        ..logErr('Field \'assets.icon\' doesn\'t exist or is empty in rush.yml',
            addSpace: true)
        ..finishNotOk('Failed');
      isInvalid = true;
    }

    if (isInvalid) {
      Utils.printFailMsg();
      exit(1);
    }
  }
}
