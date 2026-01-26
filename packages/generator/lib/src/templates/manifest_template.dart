import 'package:generator/src/models/template.dart';
import 'package:generator/src/models/workspace.dart';
import 'package:path/path.dart' as path;

class ManifestTemplate implements Template {
  @override
  Workspace workspace;

  @override
  String get content =>
      '''
<?xml version="1.0" encoding="utf-8"?>
<manifest
  package="${workspace.packageName}"
  xmlns:android="http://schemas.android.com/apk/res/android" />
    ''';

  @override
  String get filePath =>
      path.join(workspace.directory.path, 'AndroidManifest.xml');

  ManifestTemplate(this.workspace);
}
