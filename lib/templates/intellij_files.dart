import 'package:rush_cli/utils/file_extension.dart';

String getDevDepsXml(List<String> devDepJars) {
  final classes =
      devDepJars.map((el) => '<root url="jar://$el!/"/>').join('\n');
  final sources = devDepJars.map((el) {
    final file = el.replaceRange(el.length - 4, null, '-sources.jar').asFile();
    if (file.existsSync()) {
      return '<root url="jar://$file!/"/>';
    }
  }).join('\n');

  return '''
<component name="libraryTable">
  <library name="dev-deps">
    <CLASSES>
      $classes
    </CLASSES>
    <JAVADOC />
    <SOURCES>
      $sources
    </SOURCES>
  </library>
</component>
''';
}

String getDepsXml() {
  return '''
<component name="libraryTable">
  <library name="deps">
    <CLASSES>
      <root url="file://\$PROJECT_DIR\$/deps" />
    </CLASSES>
    <JAVADOC />
    <SOURCES />
    <jarDirectory url="file://\$PROJECT_DIR\$/deps" recursive="false" />
  </library>
</component>
''';
}

String getIml(String ideaDir, List<String> libXmls) {
  final libBuf = StringBuffer();
  for (final el in libXmls) {
    libBuf.write('<orderEntry type="library" name="$el" level="project" />');
  }

  return '''
<?xml version="1.0" encoding="UTF-8"?>
<module type="JAVA_MODULE" version="4">
  <component name="NewModuleRootManager" inherit-compiler-output="true">
    <exclude-output />
    <content url="file://\$MODULE_DIR\$">
      <sourceFolder url="file://\$MODULE_DIR\$/src" isTestSource="false" />
    </content>
    <orderEntry type="inheritedJdk" />
    <orderEntry type="sourceFolder" forTests="false" />
    ${libBuf.toString()}
  </component>
</module>
''';
}

String getMiscXml() {
  return '''
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="ProjectRootManager" version="2" languageLevel="JDK_8" project-jdk-name="8" project-jdk-type="JavaSDK">
    <output url="file://\$PROJECT_DIR\$/classes" />
  </component>
</project>
''';
}

String getModulesXml(String name) {
  return '''
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="ProjectModuleManager">
    <modules>
      <module fileurl="file://\$PROJECT_DIR\$/.idea/$name.iml" filepath="\$PROJECT_DIR\$/.idea/$name.iml" />
    </modules>
  </component>
</project>
''';
}

String getLibXml(
  String name,
  List<String> classes,
  String sources,
) {
  final buf = StringBuffer();
  for (final el in classes) {
    if (el.endsWith('.jar')) {
      buf.write('<root url="jar://$el!/" />');
    } else {
      buf.write('<root url="file://$el!/" />');
    }
  }

  return '''
<component name="libraryTable">
<library name="$name">
  <CLASSES>${buf.toString()}</CLASSES>
  <SOURCES><root url="jar://$sources!/" /></SOURCES>
</library>
</component>
''';
}
