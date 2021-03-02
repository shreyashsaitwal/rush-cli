String getBuildXml() {
  return '''
<?xml version="1.0" encoding="UTF-8" ?>
<project name="rush-build">
  <taskdef resource="net/sf/antcontrib/antcontrib.properties" classpath="\${antCon}" />

  <target name="javac">
    <mkdir dir="\${classes}" />
    <depend srcdir="\${extSrc}">
      <include name="**/*.java" />
    </depend>
    <javac target="7" source="7" destdir="\${classes}"
            srcdir="\${extSrc}" encoding="utf-8"
            includeantruntime="false">
      <compilerarg line="-Xlint:-options"/>
      <compilerarg line="-Aroot=\${root}"/>
      <compilerarg line="-AextName=\${extName}"/>
      <compilerarg line="-Aversion=\${version}"/>
      <compilerarg line="-Aorg=\${org}"/>
      <compilerarg line="-Aoutput=\${classes}"/>
      <classpath>
        <fileset dir="\${devDeps}">
          <include name="*.jar" />
          <include name="**/*.jar" />
        </fileset>
        <fileset dir="\${processor}">
          <include name="*.jar" />
        </fileset>
        <fileset dir="\${deps}">
          <include name="*.jar" />
        </fileset>
      </classpath>
      <include name="**/*.java" />
    </javac>
  </target>

  <target name="process" >
    <mkdir dir="\${raw}" />
    <mkdir dir="\${rawCls}" />
    <java failonerror="true" fork="true"
          classname="io.shreyash.rush.ExtensionGenerator">
      <classpath>
        <fileset dir="\${devDeps}">
          <include name="*.jar" />
        </fileset>
        <fileset dir="\${processor}">
          <include name="*.jar" />
        </fileset>
      </classpath>
      <arg path="\${classes}/simple_components.json" />
      <arg path="\${classes}/simple_components_build_info.json" />
      <arg path="\${raw}" />
      <arg path="\${classes}" />
      <arg path="\${deps}" />
      <arg path="\${rawCls}" />
      <arg value="false" />
      <arg value="\${cd}" />
    </java>
  </target>

  <target name="unjarAllLibs" depends="process" >
    <foreach target="unjarLibs" param="extension" inheritall="true">
      <path>
        <dirset dir="\${rawCls}">
          <include name="*" />
        </dirset>
      </path>
    </foreach>
  </target>

  <target name="unjarLibs">
    <basename property="extensionClassFolder" file="\${extension}" />
    <unzip dest="\${rawCls}/\${extensionClassFolder}">
      <fileset dir="\${rawCls}/\${extensionClassFolder}">
        <include name="**/*.jar" />
      </fileset>
    </unzip>
  </target>

  <target name="jarExt" depends="unjarAllLibs" >
    <basename property="extensionClassFolder" file="\${extension}" />
    <jar destfile="\${rawCls}/\${extensionClassFolder}.jar"
         basedir="\${rawCls}/\${extensionClassFolder}"
         includes="**/*.class"
         excludes="*.jar" />
    <copy file="\${rawCls}/\${extensionClassFolder}.jar"
          tofile="\${raw}/\${extensionClassFolder}/files/AndroidRuntime.jar"/>
    <if>
      <not>
        <equals arg1="\${jetifierBin}" arg2="0" />
      </not>
      <then>
        <copy todir="\${raw}/\${extensionClassFolder}.support">
          <fileset dir="\${raw}/\${extensionClassFolder}" />
        </copy>
        <antcall target="dejetify">
          <param name="androidRuntime" value="\${raw}/\${extensionClassFolder}.support/files/AndroidRuntime.jar" />
        </antcall>
      </then>
    </if>
  </target>

  <target name="dejetify">
    <if>
      <os family="windows" />
      <then>
        <property name="jetifierExe" location="\${jetifierBin}/jetifier-standalone.bat" />
      </then>
      <else>
        <property name="jetifierExe" location="\${jetifierBin}/jetifier-standalone" />
      </else>
    </if>
    <exec executable="\${jetifierExe}">
      <arg line="-i" />
      <arg path="\${androidRuntime}" />
      <arg line="-o" />
      <arg path="\${androidRuntime}" />
      <arg line="-r" />
    </exec>
  </target>

  <target name="dexExt" >
    <basename property="extensionType" file="\${extension}" suffix=".jar"/>
    <java classpath="\${d8}"
          classname="com.android.tools.r8.D8"
          fork="true"
          failonerror="true">
      <arg value="--release"/>
      <arg value="--no-desugaring"/>
      <arg value="--output"/>
      <arg value="\${raw}/\${extensionType}/classes.jar"/>
      <arg value="\${rawCls}/\${extensionType}.jar"/>
    </java>
    <java classpath="\${d8}" classname="com.android.tools.r8.D8" fork="true" failonerror="true">
      <arg value="--release" />
      <arg value="--no-desugaring" />
      <arg value="--output" />
      <arg value="\${raw}/\${extensionType}.support/classes.jar" />
      <arg value="\${rawCls}/\${extensionType}.support.jar" />
    </java>
  </target>

  <target name="assemble" >
    <mkdir dir="\${out}" />
    <basename property="extensionType" file="\${extension}" />
    <zip destfile="\${out}/\${extensionType}.aix"
         basedir="\${raw}"
         includes="\${extensionType}/"
    />
    <zip destfile="\${out}/\${extensionType}.support.aix"
          basedir="\${raw}"
          includes="\${extensionType}.support/"
    />
  </target>
</project>
''';
}