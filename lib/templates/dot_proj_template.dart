String getDotProject(String name) {
  final time = DateTime.now().toString().replaceAll('-', '').replaceAll(':', '').replaceAll('.', '').replaceAll(' ', '');
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
	<filteredResources>
		<filter>
			<id>${time.substring(time.length - 13)}</id>
			<name></name>
			<type>30</type>
			<matcher>
				<id>org.eclipse.core.resources.regexFilterMatcher</id>
				<arguments>node_modules|.git|__CREATED_BY_JAVA_LANGUAGE_SERVER__</arguments>
			</matcher>
		</filter>
	</filteredResources>
</projectDescription>

''';
}
