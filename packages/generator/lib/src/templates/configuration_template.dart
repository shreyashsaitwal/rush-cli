import 'package:change_case/change_case.dart';
import 'package:generator/src/models/template.dart';
import 'package:generator/src/models/workspace.dart';
import 'package:path/path.dart' as path;

class ConfigurationTemplate implements Template {
  @override
  Workspace workspace;

  @override
  String get content =>
      '''
description: ${workspace.name.toCapitalCase()} made with Rush.
icon: assets/icon.png
name: ${workspace.name}

# Files within the `assets` directory to be included in the build.
assets:
  - cat.png

# Configure the build variant to desugar, minify, and optimize.
build:
  desugar: true
  minify: true
  optimize: true
  version: ${workspace.version}

# Libraries marked as `compile` will be included in the archive 
# and used to build "${workspace.name.toCapitalCase()}".
#
# Those marked `runtime` will not be included in the archive.
# dependencies:
#   compile:
#     - com.google.code.gson:gson:2.13.2
#     - libs/androidx-graphics-core-1.0.4.jar
#   runtime:
#     - com.google.firebase:firebase-core:21.1.1
  ''';

  @override
  String get filePath => path.join(workspace.directory.path, 'rush.yml');

  ConfigurationTemplate(this.workspace);
}
