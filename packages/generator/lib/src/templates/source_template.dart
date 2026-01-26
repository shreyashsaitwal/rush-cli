import 'package:generator/src/models/template.dart';
import 'package:generator/src/models/workspace.dart';
import 'package:path/path.dart' as path;

class SourceTemplate implements Template {
  @override
  Workspace workspace;

  @override
  String get content =>
      '''
package ${workspace.packageName}

import com.google.appinventor.components.annotations.SimpleFunction
import com.google.appinventor.components.runtime.AndroidNonvisibleComponent
import com.google.appinventor.components.runtime.ComponentContainer
import com.google.appinventor.components.runtime.errors.YailRuntimeError
import com.google.appinventor.components.runtime.util.YailList

class ${workspace.name.toLowerCase()}(container: ComponentContainer) : AndroidNonvisibleComponent(container.`\$form`()) {

}
''';

  @override
  String get filePath => path.join(
    workspace.directory.path,
    workspace.sourceDirectory.path,
    "${workspace.name.toLowerCase()}.kt",
  );

  SourceTemplate(this.workspace);
}
