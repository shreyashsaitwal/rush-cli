String config(String name, bool enableKt) {
  return '''
version: '1.0.0'

android:
  min_sdk: 7
  compile_sdk: 31

# kotlin:
#   enable: true
#   version: '1.7.10'

# desugar: true

# Runtime dependencies of your extension. These can be local JARs or AARs stored in the deps/ directory or coordinates
# of remote Maven artifacts in <groupId>:<artifactId>:<version> format. 
# dependencies:
# - example.jar                 # Local JAR or AAR file stored in deps directory
# - com.example:foo-bar:1.2.3   # Coordinate of remote Maven artifact
''';
}

String pgRules(String org) {
  return '''
# Prevents extension classes (annotated with @ExtensionComponent) from being removed, renamed or repackged.
-keep @com.google.appinventor.components.annotations.ExtensionComponent public class * {
    public *;
}

# ProGuard sometimes (randomly) renames references to the following classes in the extensions, this rule prevents that 
# from happening. Keep this rule even if you don't use these classes in your extension.
-keeppackagenames gnu.kawa**, gnu.expr**

# Repackages all the optimized classes into $org.repackaged package in resulting AIX. Repackaging is necessary to avoid
# clashes with the other extensions that might be using same libraries as you.
-repackageclasses $org.repacked
''';
}

const String dotGitignore = '''
/out/
/.rush/
''';

String androidManifestXml(String org) {
  return '''
<?xml version="1.0" encoding="utf-8"?>
<manifest 
  xmlns:android="http://schemas.android.com/apk/res/android" 
  package="$org"
>
  <application>
    <!-- Add your application level manifest tags here. -->

  </application>
</manifest>
''';
}

// TODO: Add build instructions and other basic info
String readmeMd(String name) {
  return '''
## $name

An App Inventor 2 extension created using Rush.
''';
}
