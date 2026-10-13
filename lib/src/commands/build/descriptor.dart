import 'dart:convert';

import 'package:path/path.dart' as p;

import 'package:rush/src/utils/file_extension.dart';

class Descriptor {
  Descriptor._(this.components);

  final List<Map<String, dynamic>> components;

  String get package {
    final type = components.first['type'] as String;
    return type.substring(0, type.lastIndexOf('.'));
  }

  static Future<Descriptor?> read(String rawDir) async {
    final componentsJson = p.join(rawDir, 'components.json').asFile();
    final buildInfosJson =
        p.join(rawDir, 'files', 'component_build_infos.json').asFile();
    if (!await componentsJson.exists() || !await buildInfosJson.exists()) {
      return null;
    }
    final components = (jsonDecode(await componentsJson.readAsString()) as List)
        .cast<Map<String, dynamic>>();
    return components.isEmpty ? null : Descriptor._(components);
  }
}
