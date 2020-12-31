import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:rush_prompt/rush_prompt.dart';
import 'package:yaml/yaml.dart';

import 'is_yaml_valid.dart';

mixin GetRushYaml {
  static YamlMap data(String cd) {
    var result;

    if (File(p.join(cd, 'rush.yaml')).existsSync()) {
      result = p.join(cd, 'rush.yaml');
    } else if (File(p.join(cd, 'rush.yml')).existsSync()) {
      result = p.join(cd, 'rush.yml');
    } else {
      ThrowError(message: 'Unable to find "rush.yaml" in this directory.');
    }

    if (!IsYamlValid.check(File(result))) {
      ThrowError(
          message:
              'The "rush.yaml" file for this project isn\'t valid.\nMake sure it is properly indented and that it follows Rush\'s YAML-schema');
    }

    return loadYaml(File(result).readAsStringSync());
  }

  static File file(String cd) {
    var result;

    if (File(p.join(cd, 'rush.yaml')).existsSync()) {
      result = p.join(cd, 'rush.yaml');
    } else if (File(p.join(cd, 'rush.yml')).existsSync()) {
      result = p.join(cd, 'rush.yml');
    } else {
      ThrowError(message: 'Unable to find "rush.yaml" in this directory.');
    }

    if (!IsYamlValid.check(File(result))) {
      ThrowError(
          message:
              'The "rush.yaml" file for this project isn\'t valid.\nMake sure it is properly indented and that it follows Rush\'s YAML-schema');
    }

    return File(result);
  }
}
