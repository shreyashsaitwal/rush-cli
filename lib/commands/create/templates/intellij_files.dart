import 'package:rush_cli/resolver/artifact.dart';

String ijImlXml(String ideaDir, List<String> libXmls) {
  final libEntries = libXmls
      .map((el) =>
          '    <orderEntry type="library" name="$el" level="project" />')
      .join('\n');

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
$libEntries
  </component>
</module>
''';
}

const String ijMiscXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="ProjectRootManager" version="2" languageLevel="JDK_8" project-jdk-name="8" project-jdk-type="JavaSDK">
    <output url="file://\$PROJECT_DIR\$/classes" />
  </component>
</project>
''';

String ijModulesXml(String name) {
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

String ijDevDepsXml(Iterable<Artifact> devDeps) {
  final classesJars = devDeps
      .map((el) => '      <root url="jar://${el.classesJar}!/"/>')
      .join('\n');
  final sourcesJars = devDeps
      .where((el) => el.sourceJar != null)
      .map((el) => '      <root url="jar://${el.sourceJar}!/"/>')
      .join('\n');

  return '''
<component name="libraryTable">
  <library name="dev-deps">
    <CLASSES>
$classesJars
    </CLASSES>
    <SOURCES>
$sourcesJars
    </SOURCES>
    <JAVADOC />
  </library>
</component>
''';
}

const String ijLocalDepsXml = '''
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
