String dotProject(String name) {
  return '''
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
	<name>$name</name>
	<comment></comment>
	<projects>
	</projects>
	<buildSpec>
		<buildCommand>
			<name>org.eclipse.jdt.core.javabuilder</name>
			<arguments>
			</arguments>
		</buildCommand>
	</buildSpec>
	<natures>
		<nature>org.eclipse.jdt.core.javanature</nature>
	</natures>
</projectDescription>
''';
}

String dotClasspath(Iterable<String> classesJars, Iterable<String> sourcesJars) {
  final classes = classesJars.map((el) => '  <classpathentry kind="lib" path="$el"/>').join('\n');
  final sources = sourcesJars.map((el) => '  <classpathentry kind="lib" path="$el"/>').join('\n');
  return '''
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
  <classpathentry kind="src" path="src/" />
	<classpathentry kind="output" path=".rush/bin"/>
$classes
$sources
</classpath>
''';
}
