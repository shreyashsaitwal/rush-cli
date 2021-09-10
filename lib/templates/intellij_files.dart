import 'dart:io';

import 'package:path/path.dart' as p;

String getDevDepsXml(String _dataDir) {
  final devDepsPath = p.join(_dataDir, 'dev-deps').replaceAll('\\', '/');
  return '''
<component name="libraryTable">
  <library name="dev-deps">
    <CLASSES>
      <root url="file://$devDepsPath" />
    </CLASSES>
    <JAVADOC />
    <SOURCES />
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

String getIml(String ideaDir) {
  final libXmls = Directory(p.join(ideaDir, 'libraries'))
      .listSync()
      .whereType<File>()
      .where((el) => p.extension(el.path) == '.xml');

  final libBuf = StringBuffer();
  for (final el in libXmls) {
    libBuf.write(
        '<orderEntry type="library" name="${p.basenameWithoutExtension(el.path)}" level="project" />');
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
  List<String> javadocs,
  List<String> sources,
) {
  final jarBuf = StringBuffer();
  for (final el in classes) {
    if (el.endsWith('.jar')) {
      jarBuf.write('<root url="jar://$el!/" />');
    } else {
      jarBuf.write('<root url="file://$el!/" />');
    }
  }

  final docBufs = StringBuffer();
  for (final el in javadocs) {
    docBufs.write('<root url="jar://$el!/" />');
  }

  final sourceBuf = StringBuffer();
  for (final el in sources) {
    sourceBuf.write('<root url="jar://$el!/" />');
  }

  return '''
<component name="libraryTable">
<library name="$name">
  <CLASSES>${jarBuf.toString()}</CLASSES>
  <JAVADOC>${docBufs.toString()}</JAVADOC>
  <SOURCES>${sourceBuf.toString()}</SOURCES>
</library>
</component>
''';
}
