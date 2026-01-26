import 'package:change_case/change_case.dart';
import 'package:generator/src/models/template.dart';
import 'package:generator/src/models/workspace.dart';
import 'package:path/path.dart' as path;

class ReadMeTemplate implements Template {
  @override
  Workspace workspace;

  @override
  String get content =>
      '''
### ${workspace.name.toCapitalCase()}

A Trolly-made App Inventor extension.
  ''';

  @override
  String get filePath => path.join(workspace.directory.path, 'readme.md');

  ReadMeTemplate(this.workspace);
}
