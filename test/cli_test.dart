@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/project.dart';

const _helperEnum = '''
package {package}.helpers;

import com.google.appinventor.components.common.OptionList;

public enum Mode implements OptionList<String> {
  FAST("fast"),
  SLOW("slow");

  private final String value;

  Mode(String value) {
    this.value = value;
  }

  public String toUnderlyingValue() {
    return value;
  }
}
''';

const _extensionWithProperty = '''
package {package}

import com.google.appinventor.components.annotations.DesignerProperty
import com.google.appinventor.components.annotations.Extension
import com.google.appinventor.components.annotations.SimpleProperty
import com.google.appinventor.components.common.PropertyTypeConstants
import com.google.appinventor.components.runtime.AndroidNonvisibleComponent
import com.google.appinventor.components.runtime.ComponentContainer

@Extension(description = "Test extension", icon = "icon.png")
class {className}(container: ComponentContainer) : AndroidNonvisibleComponent(container.`\$form`()) {
    private var speed = 1

    @SimpleProperty(description = "Speed")
    fun Speed(): Int = speed

    @DesignerProperty(editorType = PropertyTypeConstants.PROPERTY_TYPE_NON_NEGATIVE_INTEGER, defaultValue = "1")
    @SimpleProperty
    fun Speed(value: Int) {
        speed = value
    }
}
''';

const _javaExtension = '''
package {package};

import com.google.appinventor.components.annotations.Extension;
import com.google.appinventor.components.annotations.SimpleFunction;
import com.google.appinventor.components.runtime.AndroidNonvisibleComponent;
import com.google.appinventor.components.runtime.ComponentContainer;
import com.google.appinventor.components.runtime.util.Continuation;

@Extension(description = "Test extension", icon = "icon.png")
public class {className} extends AndroidNonvisibleComponent {
  public {className}(ComponentContainer container) {
    super(container.\$form());
  }

{functions}
}
''';

String _fill(String template, TestProject project) => template
    .replaceAll('{package}', project.package)
    .replaceAll('{className}', project.className);

Future<ProcessResult> _buildWithFunctions(
    TestProject project, String functions) {
  project.source('${project.className}.java').writeAsStringSync(
      _fill(_javaExtension, project).replaceFirst('{functions}', functions));
  return project.build();
}

void main() {
  final projects = <TestProject>[];

  Future<TestProject> createProject(String name,
      {String language = 'kotlin', String parentPrefix = 'rush-test-'}) async {
    final project = await TestProject.create(name,
        language: language, parentPrefix: parentPrefix);
    projects.add(project);
    return project;
  }

  tearDownAll(() => Future.wait(projects.map((p) => p.delete())));

  group('exit code', () {
    test('is non-zero for an unknown command', () async {
      final result = await rush(['nonexistent'],
          workingDirectory: Directory.systemTemp.path);
      expect(result.exitCode, isNot(0));
    });

    test('is non-zero and explained when building outside a project', () async {
      final empty = await Directory.systemTemp.createTemp('rush-test-empty-');
      addTearDown(() => empty.delete(recursive: true));
      final result = await rush(['build'], workingDirectory: empty.path);
      expect(result.exitCode, isNot(0));
      expect(result.output, contains('rush.yml'));
    });

    test('is non-zero when the build fails', () async {
      final project = await createProject('broken_ext');
      project.source('${project.className}.kt').writeAsStringSync('not kotlin');
      final result = await project.build();
      expect(result.exitCode, isNot(0));
      expect(result.output, contains('BUILD FAILED'));
    });
  });

  group('build', () {
    test('keeps Kotlin classes when the project also has Java sources',
        () async {
      final project = await createProject('mixed_ext');
      project.source('helpers/Mode.java').createSync(recursive: true);
      project
          .source('helpers/Mode.java')
          .writeAsStringSync(_fill(_helperEnum, project));
      final result = await project.build();
      expect(result.exitCode, 0, reason: result.output);
      expect(
          project.runtimeClasses,
          containsAll([
            project.classFile(project.className),
            project.classFile('helpers/Mode')
          ]));
    });

    test('removes classes of deleted helpers', () async {
      final project = await createProject('helper_ext', language: 'java');
      final helper = project.source('helpers/Mode.java')
        ..createSync(recursive: true);
      helper.writeAsStringSync(_fill(_helperEnum, project));
      expect((await project.build()).exitCode, 0);
      expect(
          project.runtimeClasses, contains(project.classFile('helpers/Mode')));

      helper.deleteSync();
      final result = await project.build();
      expect(result.exitCode, 0, reason: result.output);
      expect(project.runtimeClasses,
          isNot(contains(project.classFile('helpers/Mode'))));
    });

    test('works for Kotlin projects in a path with spaces', () async {
      final project = await createProject('spaced_ext',
          parentPrefix: 'rush test with spaces ');
      final result = await project.build();
      expect(result.exitCode, 0, reason: result.output);
      expect(project.runtimeClasses,
          contains(project.classFile(project.className)));
    });

    test('can run in two projects at the same time', () async {
      final first = await createProject('first_ext', language: 'java');
      final second = await createProject('second_ext', language: 'java');
      final results = await Future.wait([first.build(), second.build()]);
      for (final result in results) {
        expect(result.exitCode, 0, reason: result.output);
      }
    });
  });

  group('component descriptor', () {
    late TestProject project;

    setUpAll(() async {
      project = await createProject('prop_ext');
      project
          .source('${project.className}.kt')
          .writeAsStringSync(_fill(_extensionWithProperty, project));
      final result = await project.build();
      if (result.exitCode != 0) fail(result.output);
    });

    test('does not mark designer properties as always sent', () {
      final property = (project.components.single['properties'] as List)
          .cast<Map<String, dynamic>>()
          .single;
      expect(property['alwaysSend'], anyOf(isNull, isFalse));
    });

    test('lists a property with a getter and setter once', () {
      final names = (project.components.single['blockProperties'] as List)
          .map((p) => p['name'])
          .toList();
      expect(names, ['Speed']);
    });
  });

  group('block types', () {
    test('reject types App Inventor has no block for', () async {
      final project = await createProject('types_ext', language: 'java');
      final result = await _buildWithFunctions(project, '''
  @SimpleFunction(description = "Schedules")
  public void Schedule(java.util.Date when) {
  }

  @SimpleFunction(description = "Types")
  public void Type(char key) {
  }

  @SimpleFunction(description = "Counts")
  public void Count(Integer times) {
  }
''');
      expect(result.exitCode, isNot(0));
      expect(result.output, contains("'java.util.Date'"));
      expect(result.output, contains("'char'"));
      expect(result.output, contains('use the primitive type int'));
      expect(result.output, isNot(contains('Exception')));
    });
  });

  group('dependencies', () {
    test('name the coordinate that could not be resolved', () async {
      final project = await createProject('missing_dep_ext', language: 'java');
      project.addDependencies(['com.example.missing:nothing:1.0.0']);
      final result = await project.build();
      expect(result.exitCode, isNot(0));
      expect(result.output, contains('com.example.missing:nothing:1.0.0'));
    });
  });

  group('bundled libraries', () {
    test('move under the extension package when only it uses them', () async {
      final project = await createProject('kotlin_ext');
      final result = await project.build();
      expect(result.exitCode, 0, reason: result.output);
      expect(project.runtimeClasses,
          anyElement(startsWith('${project.packagePath}/repacked/kotlin/')));
      expect(project.runtimeClasses.where((c) => c.startsWith('kotlin/')),
          isEmpty);
    });

    test('shrink to what the extension uses', () async {
      final project = await createProject('shrunk_ext');
      project.source('helpers/Mode.java').createSync(recursive: true);
      project
          .source('helpers/Mode.java')
          .writeAsStringSync(_fill(_helperEnum, project));
      final result = await project.build();
      expect(result.exitCode, 0, reason: result.output);
      final stdlib = project.runtimeClasses.where(
          (c) => c.startsWith('${project.packagePath}/repacked/kotlin/'));
      expect(stdlib.length, lessThan(100));
      expect(
          project.runtimeClasses, contains(project.classFile('helpers/Mode')));
    });

    test('ship as AARs when a bundled AAR depends on them', () async {
      final project = await createProject('media_ext', language: 'java');
      project.addDependencies(['androidx.media3:media3-common:1.11.1']);
      final config = project.file('rush.yml');
      config.writeAsStringSync(
          config.readAsStringSync().replaceFirst('min_sdk: 21', 'min_sdk: 23'));
      final result = await project.build();
      expect(result.exitCode, 0, reason: result.output);

      const guava = 'com.google.guava-guava-33.3.1-android.aar';
      expect(project.libraries, contains(guava));
      expect(
          utf8.decode(project
              .bundledAar(guava)
              .findFile('AndroidManifest.xml')!
              .content),
          contains('package="com.google.guava.guava"'));
      expect(
          project.runtimeClasses.where((c) => c.contains('com/google/common/')),
          isEmpty);
    });
  });

  group('optimize', () {
    test('works with a library App Inventor also ships', () async {
      final project = await createProject('gson_ext', language: 'java');
      project.addDependencies(['com.google.code.gson:gson:2.8.9']);
      final result = await project.build(['--optimize']);
      expect(result.exitCode, 0, reason: result.output);
    });

    test('works with annotations that reference the Java compiler API',
        () async {
      final project = await createProject('annotations_ext', language: 'java');
      project.addDependencies(
          ['com.google.errorprone:error_prone_annotations:2.27.0']);
      final result = await project.build(['--optimize']);
      expect(result.exitCode, 0, reason: result.output);
    });

    test('works with AARs that depend on bundled libraries', () async {
      final project = await createProject('ktx_ext');
      project.addDependencies(['androidx.core:core-ktx:1.5.0']);
      final result = await project.build(['--optimize']);
      expect(result.exitCode, 0, reason: result.output);
      expect(project.libraries,
          anyElement(startsWith('org.jetbrains.kotlin-kotlin-stdlib-')));
    });
  });

  test('new projects target Android 5.0 (API 21)', () async {
    final project = await createProject('template_ext', language: 'java');
    expect(
        project.file('rush.yml').readAsStringSync(), contains('min_sdk: 21'));
  });
}
