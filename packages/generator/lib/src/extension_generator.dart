import 'dart:async';
import 'dart:io';

import 'package:generator/src/interfaces/i_generator.dart';
import 'package:generator/src/models/template.dart';
import 'package:generator/src/models/workspace.dart';
import 'package:generator/src/templates/configuration_template.dart';
import 'package:generator/src/templates/gitignore_template.dart';
import 'package:generator/src/templates/manifest_template.dart';
import 'package:generator/src/templates/proguard_rules_template.dart';
import 'package:generator/src/templates/readme_template.dart';
import 'package:generator/src/templates/source_template.dart';

class ExtensionGenerator implements IGenerator {
  @override
  FutureOr<void> generate(Workspace workspace) async {
    final List<Template> templates = [
      ConfigurationTemplate(workspace),
      GitIgnoreTemplate(workspace),
      ManifestTemplate(workspace),
      ProguardRulesTemplate(workspace),
      ReadMeTemplate(workspace),
      SourceTemplate(workspace),
    ];

    Future.forEach(templates, (template) async {
      File file = await File(template.filePath).create(recursive: true);

      return await file.writeAsString(template.content);
    });
  }
}
