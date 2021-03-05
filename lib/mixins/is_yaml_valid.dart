import 'dart:io';

import 'package:yaml/yaml.dart';

/// Mixin to check if the rush.yaml file is valid.
mixin IsYamlValid {
  static bool check(File? yaml, YamlMap yml) {
    final valMap = {
      'name': yml['name'],
      'desc': yml['description'],
      'version': yml['version'],
      'assets': yml['assets'],
      // 'deps': yml['dependencies'],
    };

    for (final entry in valMap.entries) {
      final key = entry.key;
      final val = entry.value;

      switch (key) {
        case 'version':
          if (val is! YamlMap) {
            return false;
          } else if (val['number'] is String) {
            if (val['number'] != 'auto') {
              return false;
            }
          } else if (val['number'] is! int) {
            return false;
          }
          break;

        case 'assets':
          if (val is! YamlMap) {
            return false;
          } else if (val['icon'] is! String) {
            return false;
          }
          break;

        // case 'deps':
        //   if (val is! YamlList) {
        //     print(key);
        //     return false;
        //   }
        //   (val as YamlList).forEach((dep) {
        //     if (dep is! YamlMap) {
        //     print(key);
        //       return false;
        //     } else if (!(dep as YamlMap).containsKey('group') ||
        //         !(dep as YamlMap).containsKey('version')) {
        //     print(key);
        //       return false;
        //     }
        //   });
        //   break;

        default:
          return true;
      }
    }
    return true;
  }
}
