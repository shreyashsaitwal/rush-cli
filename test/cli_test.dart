@Timeout(Duration(minutes: 3))
library;

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

String _fill(String template, TestProject project) => template
    .replaceAll('{package}', project.package)
    .replaceAll('{className}', project.className);

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

  group('dependencies', () {
    test('name the coordinate that could not be resolved', () async {
      final project = await createProject('missing_dep_ext', language: 'java');
      final config = project.file('rush.yml');
      config.writeAsStringSync(config.readAsStringSync().replaceFirst(
            '#dependencies:',
            'dependencies:\n- com.example.missing:nothing:1.0.0',
          ));
      final result = await project.build();
      expect(result.exitCode, isNot(0));
      expect(result.output, contains('com.example.missing:nothing:1.0.0'));
    });
  });

  test('new projects target Android 5.0 (API 21)', () async {
    final project = await createProject('template_ext', language: 'java');
    expect(
        project.file('rush.yml').readAsStringSync(), contains('min_sdk: 21'));
  });
}
