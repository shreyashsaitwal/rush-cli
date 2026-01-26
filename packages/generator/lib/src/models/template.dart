import 'package:generator/src/models/workspace.dart';

abstract interface class Template {
  String get content;
  String get filePath;

  late final Workspace workspace;
}
