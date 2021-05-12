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

String getDevDepsXml() {
  return '''
<component name="libraryTable">
  <library name="deps">
    <CLASSES>
      <root url="file://\$PROJECT_DIR\$/.rush/dev-deps" />
    </CLASSES>
    <JAVADOC />
    <SOURCES />
    <jarDirectory url="file://\$PROJECT_DIR\$/.rush/dev-deps" recursive="false" />
  </library>
</component>
''';
}
