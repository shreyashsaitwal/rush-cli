String ijImlXml(List<String> libs) {
  final libEntries = libs
      .map((el) =>
          '        <orderEntry type="library" name="$el" level="project" />')
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

String ijProvidedDepsXml(
    Iterable<String> classesJars, Iterable<String> sourcesJars) {
  final classes = classesJars
      .map((el) => '            <root url="jar://$el!/"/>')
      .join('\n');
  final sources = sourcesJars
      .map((el) => '            <root url="jar://$el!/"/>')
      .join('\n');

  return '''
<component name="libraryTable">
    <library name="provided-deps">
        <CLASSES>
$classes
        </CLASSES>
        <SOURCES>
$sources
        </SOURCES>
        <JAVADOC />
    </library>
</component>
''';
}

const String ijLocalDepsXml = '''
<component name="libraryTable">
    <library name="local-deps">
        <CLASSES>
            <root url="file://\$PROJECT_DIR\$/deps" />
        </CLASSES>
        <JAVADOC />
        <SOURCES />
        <jarDirectory url="file://\$PROJECT_DIR\$/deps" recursive="false" />
    </library>
</component>
''';
