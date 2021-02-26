String getBuildXml() {
  return '''
<?xml version = "1.0" encoding = "UTF-8" ?>
<project name = "rush-build">
  <taskdef resource = "net/sf/antcontrib/antcontrib.properties" classpath = "\${antCon}" />

  <target name = "javac">
    <mkdir dir = "\${classes}" />
    <depend srcdir = "\${extSrc}">
      <include name = "**/*.java" />
    </depend>
    <javac target = "7" source = "7" destdir = "\${classes}"
            srcdir = "\${extSrc}" encoding = "utf-8"
            includeantruntime = "false">
      <compilerarg line="-Xlint:-options"/>
      <compilerarg line="-Aroot=\${root}"/>
      <compilerarg line="-AextName=\${extName}"/>
      <compilerarg line="-Aversion=\${version}"/>
      <compilerarg line="-Aorg=\${org}"/>
      <compilerarg line="-Aoutput=\${classes}"/>
      <classpath>
        <fileset dir = "\${devDeps}">
          <include name = "*.jar" />
          <include name = "**/*.jar" />
        </fileset>
        <fileset dir = "\${processor}">
          <include name = "*.jar" />
        </fileset>
        <fileset dir = "\${deps}">
          <include name = "*.jar" />
        </fileset>
      </classpath>
      <include name = "**/*.java" />
    </javac>
  </target>

  <target name = "process" >
    <mkdir dir = "\${raw}" />
    <mkdir dir = "\${rawCls}" />
    <java failonerror = "true" fork = "true"
          classname = "io.shreyash.rush.ExtensionGenerator">
      <classpath>
        <fileset dir = "\${devDeps}">
          <include name = "*.jar" />
        </fileset>
        <fileset dir = "\${processor}">
          <include name = "*.jar" />
        </fileset>
      </classpath>
      <arg path = "\${classes}/simple_components.json" />
      <arg path = "\${classes}/simple_components_build_info.json" />
      <arg path = "\${raw}" />
      <arg path = "\${classes}" />
      <arg path = "\${deps}" />
      <arg path = "\${rawCls}" />
      <arg value = "false" />
      <arg value = "\${cd}" />
    </java>
  </target>

  <target name = "unjarAllLibs" depends = "process" >
    <foreach target = "unjarLibs" param = "extension" inheritall = "true">
      <path>
        <dirset dir = "\${rawCls}">
          <include name = "*" />
        </dirset>
      </path>
    </foreach>
  </target>

  <target name = "unjarLibs">
    <basename property = "extensionClassFolder" file = "\${extension}" />
    <unzip dest = "\${rawCls}/\${extensionClassFolder}">
      <fileset dir = "\${rawCls}/\${extensionClassFolder}">
        <include name = "**/*.jar" />
      </fileset>
    </unzip>
  </target>

  <target name = "jarExt" depends = "unjarAllLibs" >
    <basename property = "extensionClassFolder" file = "\${extension}" />
    <jar destfile = "\${rawCls}/\${extensionClassFolder}.jar"
         basedir = "\${rawCls}/\${extensionClassFolder}"
         includes = "**/*.class"
         excludes = "*.jar" />
    <copy file = "\${rawCls}/\${extensionClassFolder}.jar"
          tofile = "\${raw}/\${extensionClassFolder}/files/AndroidRuntime.jar"/>
  </target>

  <target name = "dexExt" >
    <basename property = "extensionType" file = "\${extension}" suffix = ".jar"/>
    <java classpath="\${d8}"
          classname="com.android.tools.r8.D8"
          fork="true"
          failonerror="true">
      <arg value="--release"/>
      <arg value="--no-desugaring"/>
      <arg value="--lib"/>
      <arg value="lib/appinventor/android.jar"/>
      <arg value="--output"/>
      <arg value="\${ExternalComponent.dir}/\${extensionType}/classes.jar"/>
      <arg value="\${ExternalComponent-class.dir}/\${extensionType}.jar"/>
    </java>
  </target>

  <target name = "assemble" >
    <mkdir dir = "\${out}" />
    <basename property = "extensionType" file = "\${extension}" />
    <zip destfile = "\${out}/\${extensionType}.aix"
         basedir = "\${raw}"
         includes = "\${extensionType}/"
    />
  </target>
</project>

''';
}
