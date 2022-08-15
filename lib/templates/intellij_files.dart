import 'dart:io';

import 'package:path/path.dart' as p;

String getDevDepsXml(String dataDir) {
  final devDepsPath = p.join(dataDir, 'dev-deps').replaceAll('\\', '/');
  return '''
<component name="libraryTable">
  <library name="dev-deps">
    <CLASSES>
      <root url="file://$devDepsPath" />
    </CLASSES>
    <JAVADOC />
    <SOURCES>
      <root url="jar://$devDepsPath/rush/runtime-sources.jar!/" />
      <root url="jar://$devDepsPath/rush/annotations-sources.jar!/" />
      <root url="jar://$devDepsPath/kotlin/kotlin-stdlib-sources.jar!/" />
    </SOURCES>
    <jarDirectory url="file://$devDepsPath" recursive="true" />
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
