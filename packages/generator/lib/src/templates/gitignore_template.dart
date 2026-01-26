import 'package:generator/src/models/template.dart';
import 'package:generator/src/models/workspace.dart';
import 'package:path/path.dart' as path;

class GitIgnoreTemplate implements Template {
  @override
  Workspace workspace;

  @override
  String get content => '''
# Build directory
build
''';

  @override
  String get filePath => path.join(workspace.directory.path, '.gitignore');

  GitIgnoreTemplate(this.workspace);
}
