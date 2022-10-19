import 'package:rush_cli/src/services/libs_service.dart';
import 'package:rush_cli/src/utils/constants.dart';

String config(bool enableKt) {
  return '''
# This is the version name of your extension. You should update it everytime you
# publish a new version of your extension.
version: '1.0.0'

# The minimum Android SDK level your extension supports. Minimum SDK defined in
# AndroidManifest.xml is ignored, you should always define it here.
min_sdk: 7

# Desuagring allows you to use Java 8 language features in your extension. You 
# also need to enable desugaring if any of your dependencies use Java 8 language
# features.
# desugar: true
${!enableKt ? '' : '''

# Kotlin specific configuration.
kotlin:
    compiler_version: '$defaultKtVersion'
'''}
# External libraries your extension depends on. These can be local JARs / AARs
# stored in the "deps" directory or coordinates of remote Maven artifacts in
# <groupId>:<artifactId>:<version> format. 
${enableKt ? 'dependencies:' : '# dependencies:'}
${enableKt ? '- $kotlinGroupId:kotlin-stdlib:$defaultKtVersion\n' : ''}# - example.jar                 # Local JAR or AAR file stored in "deps" directory
# - com.example:foo-bar:1.2.3   # Coordinate of some remote Maven artifact

# Default Maven repositories includes Maven Central, Google Maven, JitPack and 
# JCenter. If the library you want to use is not available in these repositories,
# you can add additional repositories by specifying their URLs here.
# repositories:
# - https://jitpack.io

# Assets that your extension needs. Every asset file must be stored in the assets
# directory as well as declared here. Assets can be of any type.
# assets:
# - data.json

# Homepage of your extension. This may be the announcement thread on community 
# forums or a link to your GitHub repository.
# homepage: https://github.com/shreyashsaitwal/rush-cli

# Path to the license file of your extension. This should be a path to a local file
# or link to something hosted online.
# license: LICENSE.txt

# Similar to dependencies, except libraries defined as comptime (compile-time)
# are only available during compilation and not included in the resulting AIX.
# comptime_dependencies:
# - com.example:foo-bar:1.2.3
''';
}

String pgRules(String org) {
  return '''
# Prevents extension classes (annotated with @ExtensionComponent) from being 
# removed, renamed or repackged.
-keep @com.google.appinventor.components.annotations.ExtensionComponent public class * {
    public *;
}

# ProGuard sometimes (randomly) renames references to the following classes in 
# the extensions, this rule prevents that from happening. Keep this rule even
# if you don't use these classes in your extension.
-keeppackagenames gnu.kawa**, gnu.expr**

# Repackages all the optimized classes into $org.repackaged package in resulting
# AIX. Repackaging is necessary to avoid clashes with the other extensions that
# might be using same libraries as you.
-repackageclasses $org.repacked
''';
}

const String dotGitignore = '''
/out
/.rush
''';

String androidManifestXml(String org) {
  return '''
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="$org">

    <application>
        <!-- You can use any manifest tag that goes inside the <application> tag -->
        <!-- <service android:name="com.example.MyService"> ... </service> -->
    </application>

    <!-- Other than <application> level tags, you can use <uses-permission> & <queries> tags -->
    <!-- <uses-permission android:name="android.permission.SEND_SMS"/> -->
    <!-- <queries> ... </queries> -->

</manifest>
''';
}

// TODO: Add build instructions and other basic info
String readmeMd(String name) {
  return '''
# $name

An App Inventor 2 extension created using Rush.
''';
}
