import 'package:generator/src/models/template.dart';
import 'package:generator/src/models/workspace.dart';
import 'package:path/path.dart' as path;

class ProguardRulesTemplate implements Template {
  @override
  Workspace workspace;

  @override
  String get content =>
      '''
keep public class ${workspace.packageName} {
  public *;
}

-allowaccessmodification
-mergeinterfacesaggressively
-optimizationpasses 2
-repackageclasses ${workspace.packageName}
''';

  @override
  String get filePath =>
      path.join(workspace.directory.path, 'proguard-rules.pro');

  ProguardRulesTemplate(this.workspace);
}
