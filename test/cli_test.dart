@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:test/test.dart';

import 'support/project.dart';

const _helperEnum = '''
package {package}.helpers;

import com.google.appinventor.components.common.OptionList;

public enum Mode implements OptionList<String> {
  /** Moves quickly. */
  FAST("fast"),
  /** Moves carefully. */
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
import com.google.appinventor.components.annotations.PropertyCategory
import com.google.appinventor.components.annotations.SimpleFunction
import com.google.appinventor.components.annotations.SimpleProperty
import com.google.appinventor.components.common.PropertyTypeConstants
import com.google.appinventor.components.runtime.AndroidNonvisibleComponent
import com.google.appinventor.components.runtime.ComponentContainer

@Extension(description = "Test extension", icon = "icon.png")
class {className}(container: ComponentContainer) : AndroidNonvisibleComponent(container.`\$form`()) {
    private var speed = 1

    @SimpleProperty(description = "Speed", category = PropertyCategory.APPEARANCE)
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

const _documentedExtension = '''
package {package};

import com.google.appinventor.components.annotations.DesignerProperty;
import com.google.appinventor.components.annotations.Extension;
import com.google.appinventor.components.annotations.Options;
import com.google.appinventor.components.annotations.SimpleEvent;
import com.google.appinventor.components.annotations.SimpleFunction;
import com.google.appinventor.components.annotations.SimpleProperty;
import com.google.appinventor.components.common.PropertyTypeConstants;
import com.google.appinventor.components.runtime.AndroidNonvisibleComponent;
import com.google.appinventor.components.runtime.ComponentContainer;
import com.google.appinventor.components.runtime.EventDispatcher;
import {package}.helpers.Mode;

@Extension(description = "Counts things.", icon = "icon.png")
public class {className} extends AndroidNonvisibleComponent {
  private int step = 1;

  public {className}(ComponentContainer container) {
    super(container.\$form());
  }

  @SimpleFunction(description = "Adds the step to a number.")
  public int Add(int number) {
    return number + step;
  }

  @SimpleFunction(description = "Changes how counting moves.")
  public void SetMode(@Options(Mode.class) String mode) {
  }

  @SimpleEvent(description = "The count reached a limit.")
  public void LimitReached(int limit, String reason) {
    EventDispatcher.dispatchEvent(this, "LimitReached", limit, reason);
  }

  @SimpleProperty(description = "Amount added each time.")
  public int Step() {
    return step;
  }

  @DesignerProperty(editorType = PropertyTypeConstants.PROPERTY_TYPE_NON_NEGATIVE_INTEGER, defaultValue = "1")
  @SimpleProperty
  public void Step(int value) {
    step = value;
  }
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

  group('errors', () {
    Future<String> failedBuild(TestProject project) async {
      final result = await project.build();
      expect(result.exitCode, 1, reason: result.output);
      expect(result.output, isNot(contains('Exception')));
      return result.output;
    }

    void editConfig(TestProject project, String from, String to) {
      final config = project.file('rush.yml');
      config
          .writeAsStringSync(config.readAsStringSync().replaceFirst(from, to));
    }

    test('explain that no class has @Extension', () async {
      final project = await createProject('unannotated_ext', language: 'java');
      final source = project.source('${project.className}.java');
      source.writeAsStringSync(source
          .readAsStringSync()
          .replaceFirst(RegExp(r'@Extension\([^)]*\)'), ''));
      expect(await failedBuild(project), contains('@Extension'));
    });

    test('point at the rush.yml line of a configuration mistake', () async {
      final project = await createProject('typo_ext', language: 'java');
      editConfig(project, 'min_sdk:', 'min_sdkk:');
      expect(
          await failedBuild(project),
          allOf(
              contains('rush.yml'), contains('line 7'), contains('min_sdkk')));
    });

    test('name a missing asset', () async {
      final project = await createProject('no_asset_ext', language: 'java');
      editConfig(project, '#assets:', 'assets:\n- missing.txt\n#assets:');
      expect(await failedBuild(project), contains('assets/missing.txt'));
    });

    test('name a missing local library', () async {
      final project = await createProject('no_jar_ext', language: 'java');
      editConfig(project, '#dependencies:', 'dependencies:\n- missing.jar');
      expect(await failedBuild(project), contains('deps/missing.jar'));
    });

    test('list unresolvable dependencies', () async {
      final project = await createProject('no_artifact_ext', language: 'java');
      project.addDependencies(['com.example.missing:nothing:9.9.9']);
      expect(await failedBuild(project),
          contains('com.example.missing:nothing:9.9.9'));
    });
  });

  group('output', () {
    final escape = RegExp('\x1b');

    test('is plain text when not written to a terminal', () async {
      final project = await createProject('piped_ext');
      final result = await Process.run(rushBin, ['build'],
          workingDirectory: project.dir.path);
      expect(result.exitCode, 0, reason: result.output);
      expect(result.output, isNot(contains(escape)));
      expect(result.output, isNot(contains('/_/')));
      expect(result.output, contains('Compiling sources'));
      expect(result.output, isNot(contains(RegExp(r' $', multiLine: true))));
    });

    test('is colored when color is requested', () async {
      final result = await Process.run(rushBin, ['--color', 'clean'],
          workingDirectory: Directory.systemTemp.path);
      expect(result.output, contains(escape));
    });

    test('of clean is plain text when not written to a terminal', () async {
      final project = await createProject('clean_ext');
      final result = await Process.run(rushBin, ['clean'],
          workingDirectory: project.dir.path);
      expect(result.exitCode, 0, reason: result.output);
      expect(result.output, isNot(contains(escape)));
      expect(result.output, contains('Deleted build files and caches'));
    });
  });

  test('clean works on a project that was never built', () async {
    final project = await createProject('unbuilt_ext');
    final result = await rush(['clean'], workingDirectory: project.dir.path);
    expect(result.exitCode, 0, reason: result.output);
  });

  test('create asks for missing options only in a terminal', () async {
    final parent = await Directory.systemTemp.createTemp('rush-test-');
    addTearDown(() => parent.delete(recursive: true));
    final result = await rush(['create', 'prompt_ext', '-p', 'com.example'],
            workingDirectory: parent.path)
        .timeout(const Duration(seconds: 20));
    expect(result.exitCode, 64, reason: result.output);
    expect(result.output, contains('--language'));
  });

  test('create adds a GitHub workflow that builds with Rush', () async {
    final project = await createProject('workflow_ext');
    final workflow = File('${project.dir.path}/.github/workflows/build.yml')
        .readAsStringSync();
    expect(workflow, contains('uses: zainulhassan815/rush-cli@v2'));
    expect(workflow, contains('run: rush build'));
  });

  group('agent instructions', () {
    test('are part of new projects', () async {
      final project = await createProject('agent_ext', language: 'java');
      expect(project.file('AGENTS.md').readAsStringSync(),
          contains('.claude/skills/rush/SKILL.md'));
      expect(project.file('CLAUDE.md').readAsStringSync(), '@AGENTS.md\n');
      expect(project.file('.claude/skills/rush/SKILL.md').readAsStringSync(),
          startsWith('---\nname: rush\n'));
    });

    test('are refreshed by rush agents without touching AGENTS.md', () async {
      final project =
          await createProject('agent_refresh_ext', language: 'java');
      project.file('AGENTS.md').writeAsStringSync('My own notes\n');
      project.file('CLAUDE.md').deleteSync();
      final skill = project.file('.claude/skills/rush/SKILL.md')
        ..writeAsStringSync('outdated');

      final result = await rush(['agents'], workingDirectory: project.dir.path);
      expect(result.exitCode, 0, reason: result.output);
      expect(project.file('AGENTS.md').readAsStringSync(), 'My own notes\n');
      expect(project.file('CLAUDE.md').readAsStringSync(), '@AGENTS.md\n');
      expect(skill.readAsStringSync(), startsWith('---\nname: rush\n'));
    });

    test('need a project', () async {
      final empty = await Directory.systemTemp.createTemp('rush-test-empty-');
      addTearDown(() => empty.delete(recursive: true));
      final result = await rush(['agents'], workingDirectory: empty.path);
      expect(result.exitCode, 1, reason: result.output);
      expect(result.output, contains('rush.yml'));
    });
  });

  test('build warns about rush.yml keys that have no effect', () async {
    final project = await createProject('ignored_keys_ext', language: 'java');
    final config = project.file('rush.yml');
    config.writeAsStringSync(
        '${config.readAsStringSync()}\nauthors:\n- Jane Doe\ndesugar: true\n');
    final result = await project.build();
    expect(result.exitCode, 0, reason: result.output);
    expect(result.output, contains('`authors` in rush.yml has no effect'));
    expect(result.output, contains('`desugar` in rush.yml has no effect'));
  });

  test('an empty RUSH_AI2_RUNTIME_ZIP downloads the runtime', () async {
    final home = await Directory.systemTemp.createTemp('rush-home-');
    addTearDown(() => home.delete(recursive: true));
    Directory('${home.path}/libs').createSync();
    final sync = await Process.start(
        rushBin, ['--no-color', 'deps', 'sync', '--dev-deps'],
        workingDirectory: home.path,
        environment: {'RUSH_HOME': home.path, 'RUSH_AI2_RUNTIME_ZIP': ''});
    final output = StringBuffer();
    final downloading = Completer<bool>();
    for (final stream in [sync.stdout, sync.stderr]) {
      stream.transform(utf8.decoder).listen((text) {
        output.write(text);
        if (output.toString().contains('Downloading App Inventor runtime') &&
            !downloading.isCompleted) {
          downloading.complete(true);
        }
      });
    }
    unawaited(sync.exitCode.then((_) {
      if (!downloading.isCompleted) downloading.complete(false);
    }));
    final started = await downloading.future;
    sync.kill();
    await sync.exitCode;
    expect(started, isTrue, reason: output.toString());
  });

  test('build explains that it needs a JDK', () async {
    final project = await createProject('no_jdk_ext', language: 'java');
    final missingJdk = '${project.dir.path}${Platform.pathSeparator}no-jdk';
    final result = await project.build([], {'JAVA_HOME': missingJdk});
    expect(result.exitCode, 1, reason: result.output);
    expect(result.output, contains('Could not run `$missingJdk'));
    expect(result.output, contains('Rush needs JDK 17 or newer'));
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

    test('compiles Java 17 language features', () async {
      final project = await createProject('records_ext', language: 'java');
      final result = await _buildWithFunctions(project, '''
  record Point(int x, int y) {}

  @SimpleFunction
  public String Describe(int x) {
    Object point = new Point(x, x);
    var size = switch (x) {
      case 0 -> "none";
      default -> "some";
    };
    if (point instanceof Point p) {
      return p + " " + size;
    }
    return size;
  }
''');
      expect(result.exitCode, 0, reason: result.output);
      expect(
          project.runtimeClasses,
          contains(
              '${project.packagePath}/repacked/com/android/tools/r8/RecordTag.class'));
      expect(project.runtimeClasses.where((c) => c.startsWith('com/android/')),
          isEmpty);
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

    test('recompiles helpers after the build directory is deleted', () async {
      final project = await createProject('rebuilt_ext');
      project.source('helpers/Mode.java').createSync(recursive: true);
      project
          .source('helpers/Mode.java')
          .writeAsStringSync(_fill(_helperEnum, project));
      project.source('${project.className}.kt').writeAsStringSync(
          _fill(_extensionWithProperty, project).replaceFirst(
              '    private var speed = 1',
              '    @SimpleFunction(description = "Moves")\n'
                  '    fun Move(mode: ${project.package}.helpers.Mode) {}\n\n'
                  '    private var speed = 1'));
      expect((await project.build()).exitCode, 0);

      Directory('${project.dir.path}/.rush/build').deleteSync(recursive: true);
      final result = await project.build();
      expect(result.exitCode, 0, reason: result.output);
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

    test('puts properties in their category', () {
      final property = (project.components.single['blockProperties'] as List)
          .cast<Map<String, dynamic>>()
          .single;
      expect(property['category'], 'Appearance');
    });

    test('lists a property with a getter and setter once', () {
      final names = (project.components.single['blockProperties'] as List)
          .map((p) => p['name'])
          .toList();
      expect(names, ['Speed']);
    });
  });

  group('block types', () {
    test('make functions with a continuation asynchronous', () async {
      final project = await createProject('async_ext', language: 'java');
      final result = await _buildWithFunctions(project, '''
  @SimpleFunction(description = "Waits")
  public void Wait(int millis, Continuation<Void> done) {
    done.call(null);
  }

  @SimpleFunction(description = "Fetches")
  public void Fetch(String url, Continuation<String> result) {
    result.call(url);
  }
''');
      expect(result.exitCode, 0, reason: result.output);
      final methods = {
        for (final m in (project.components.single['methods'] as List)
            .cast<Map<String, dynamic>>())
          m['name']: m
      };
      expect(methods['Wait'], containsPair('continuation', true));
      expect(methods['Wait'], isNot(contains('returnType')));
      expect(methods['Wait']!['params'], [
        {'name': 'millis', 'type': 'number'}
      ]);
      expect(methods['Fetch'], containsPair('continuation', true));
      expect(methods['Fetch'], containsPair('returnType', 'text'));
    });

    test('give continuations of boxed types block result types', () async {
      final project = await createProject('boxed_async_ext', language: 'java');
      final result = await _buildWithFunctions(project, '''
  @SimpleFunction(description = "Counts")
  public void Count(Continuation<Integer> result) {
    result.call(1);
  }

  @SimpleFunction(description = "Checks")
  public void Check(Continuation<Boolean> result) {
    result.call(true);
  }
''');
      expect(result.exitCode, 0, reason: result.output);
      final returnTypes = {
        for (final m in (project.components.single['methods'] as List)
            .cast<Map<String, dynamic>>())
          m['name']: m['returnType']
      };
      expect(returnTypes, {'Count': 'number', 'Check': 'boolean'});
    });

    test('explain that dropdown enums belong in a helpers directory', () async {
      final project = await createProject('misplaced_ext', language: 'java');
      project.source('options/Mode.java')
        ..createSync(recursive: true)
        ..writeAsStringSync(
            _fill(_helperEnum, project).replaceFirst('.helpers;', '.options;'));
      final result = await _buildWithFunctions(project, '''
  @SimpleFunction(description = "Moves")
  public void Move(${project.package}.options.Mode mode) {
  }
''');
      expect(result.exitCode, 1, reason: result.output);
      expect(
          result.output,
          contains('Dropdown enum ${project.package}.options.Mode must be in '
              'a directory named `helpers`'));
    });

    test('describe dropdown options and honor @Options on getters', () async {
      final project = await createProject('options_ext', language: 'java');
      project.source('helpers/Mode.java').createSync(recursive: true);
      project
          .source('helpers/Mode.java')
          .writeAsStringSync(_fill(_helperEnum, project));
      final result = await _buildWithFunctions(project, '''
  @SimpleFunction(description = "Moves")
  public void Move(${project.package}.helpers.Mode mode) {
  }

  @com.google.appinventor.components.annotations.SimpleProperty(description = "Mode")
  @com.google.appinventor.components.annotations.Options(${project.package}.helpers.Mode.class)
  public String CurrentMode() {
    return "fast";
  }
''');
      expect(result.exitCode, 0, reason: result.output);
      final component = project.components.single;
      final options = (component['methods'] as List).single['params'][0]
          ['helper']['data']['options'] as List;
      expect(options.map((o) => o['description']),
          ['Moves quickly.', 'Moves carefully.']);
      final property = (component['blockProperties'] as List).single;
      expect(property['helper']?['data']?['className'],
          '${project.package}.helpers.Mode');
    });

    test('honor @Options on Kotlin getters', () async {
      final project = await createProject('kotlin_options_ext');
      project.source('helpers/Mode.java').createSync(recursive: true);
      project
          .source('helpers/Mode.java')
          .writeAsStringSync(_fill(_helperEnum, project));
      project.source('${project.className}.kt').writeAsStringSync('''
package ${project.package}

import ${project.package}.helpers.Mode
import com.google.appinventor.components.annotations.Extension
import com.google.appinventor.components.annotations.Options
import com.google.appinventor.components.annotations.SimpleProperty
import com.google.appinventor.components.runtime.AndroidNonvisibleComponent
import com.google.appinventor.components.runtime.ComponentContainer

@Extension(description = "Test extension", icon = "icon.png")
class ${project.className}(container: ComponentContainer) : AndroidNonvisibleComponent(container.`\$form`()) {
    @SimpleProperty(description = "Mode")
    @Options(Mode::class)
    fun CurrentMode(): String = "fast"
}
''');
      final result = await project.build();
      expect(result.exitCode, 0, reason: result.output);
      final property =
          (project.components.single['blockProperties'] as List).single;
      expect(property['helper']?['data']?['className'],
          '${project.package}.helpers.Mode');
    });

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

    test('report Kotlin errors at the Kotlin source', () async {
      final project = await createProject('kotlin_types_ext');
      final source = project.source('${project.className}.kt');
      source.writeAsStringSync(source.readAsStringSync().replaceFirst(
          'fun SumAll(listOfInts: YailList)',
          'fun SumAll(listOfInts: YailList, times: Int?)'));
      final result = await project.build();
      expect(result.exitCode, isNot(0));
      expect(result.output, contains('${project.className}.kt:'));
      expect(result.output, isNot(contains('kapt')));
    });
  });

  group('extension descriptor', () {
    test('is documented in Markdown next to the AIX', () async {
      final project = await createProject('docs_ext', language: 'java');
      project
          .source('${project.className}.java')
          .writeAsStringSync(_fill(_documentedExtension, project));
      project.source('helpers/Mode.java')
        ..createSync(recursive: true)
        ..writeAsStringSync(_fill(_helperEnum, project));
      final result = await project.build();
      expect(result.exitCode, 0, reason: result.output);
      expect(
          project.file('out/${project.package}.md').readAsStringSync(),
          allOf([
            contains('# DocsExt\n\n<p>Counts things.</p>'),
            contains('### Add(number)\n\nAdds the step to a number.'),
            contains('| number | number |'),
            contains('Returns `number`.'),
            contains('### LimitReached(limit, reason)'),
            contains('| reason | text |'),
            contains('### Step\n\nAmount added each time.'),
            contains('`number`, read-write, designer default `1`.'),
            contains('| mode | Mode |'),
            contains('## Dropdowns\n\n### Mode\n\n'
                '| Option | Value | Description |\n'
                '|---|---|---|\n'
                '| FAST | `fast` | Moves quickly. |\n'
                '| SLOW | `slow` | Moves carefully. |'),
          ]));
    });

    test('takes metadata from rush.yml', () async {
      final project = await createProject('metadata_ext', language: 'java');
      project.file('assets/data.txt').writeAsStringSync('data');
      project.file('rush.yml').writeAsStringSync('''
version: '2.3.0'
min_sdk: 24
homepage: https://example.com/ext
assets:
- data.txt
''');
      final result = await project.build();
      expect(result.exitCode, 0, reason: result.output);
      expect(
          project.components.single,
          allOf(
            containsPair('versionName', '2.3.0'),
            containsPair('helpUrl', 'https://example.com/ext'),
            containsPair('androidMinSdk', '24'),
          ));
      expect(project.buildInfo['assets'], ['data.txt']);
      expect(project.buildInfo['androidMinSdk'], ['24']);
    });

    test('links the license file', () async {
      final project = await createProject('license_ext', language: 'java');
      project.file('LICENSE.txt').writeAsStringSync('MIT');
      final config = project.file('rush.yml');
      config.writeAsStringSync(config
          .readAsStringSync()
          .replaceFirst('#license: LICENSE.txt', 'license: LICENSE.txt'));
      final result = await project.build();
      expect(result.exitCode, 0, reason: result.output);
      expect(project.components.single['licenseName'], 'aiwebres/LICENSE');
      expect(project.aix.files.map((f) => f.name),
          contains('${project.package}/aiwebres/LICENSE'));
    });

    test('uses the default icon when none is set', () async {
      final project = await createProject('iconless_ext', language: 'java');
      final source = project.source('${project.className}.java');
      source.writeAsStringSync(source
          .readAsStringSync()
          .replaceFirst(RegExp(r',\s*icon = "icon.png"'), ''));
      final result = await project.build();
      expect(result.exitCode, 0, reason: result.output);
      expect(project.components.single['iconName'], 'images/extension.png');
    });

    test('requires all extensions to share a package', () async {
      final project = await createProject('split_ext', language: 'java');
      project.source('other/Other.java').createSync(recursive: true);
      project.source('other/Other.java').writeAsStringSync(
          _fill(_javaExtension, project)
              .replaceFirst('package ${project.package};',
                  'package ${project.package}.other;')
              .replaceAll(project.className, 'Other')
              .replaceFirst('{functions}', ''));
      final result = await project.build();
      expect(result.exitCode, isNot(0));
      expect(result.output, contains('${project.package}.other'));
      expect(result.output, isNot(contains('Exception')));
    });

    test('names a missing icon file', () async {
      final project = await createProject('missing_icon_ext', language: 'java');
      final source = project.source('${project.className}.java');
      source.writeAsStringSync(source
          .readAsStringSync()
          .replaceFirst('icon = "icon.png"', 'icon = "missing.png"'));
      final result = await project.build();
      expect(result.exitCode, isNot(0));
      expect(result.output, contains('missing.png'));
      expect(result.output, isNot(contains('Exception')));
    });
  });

  group('manifest', () {
    late TestProject project;
    late ProcessResult build;

    setUpAll(() async {
      project = await createProject('manifest_ext', language: 'java');
      project.file('src/AndroidManifest.xml').writeAsStringSync('''
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="${project.package}">
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28"/>
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation"/>
    <uses-feature android:name="android.hardware.camera" android:required="false"/>
    <application>
        <meta-data android:name="greeting" android:value="Tom &amp; &quot;Jerry&quot; &lt;3"/>
    </application>
</manifest>
''');
      build = await project.build();
      if (build.exitCode != 0) fail(build.output);
    });

    test('keeps permission constraints', () {
      expect(project.buildInfo['permissionConstraints'], {
        'android.permission.READ_EXTERNAL_STORAGE': {'maxSdkVersion': 32},
        'android.permission.BLUETOOTH_SCAN': {
          'usesPermissionFlags': 'neverForLocation'
        },
      });
    });

    test('leaves the storage write limit to App Inventor', () {
      expect(build.output, contains('WRITE_EXTERNAL_STORAGE'));
    });

    test('keeps features', () {
      expect(project.buildInfo['features'], [
        allOf(contains('android:name="android.hardware.camera"'),
            contains('android:required="false"'))
      ]);
    });

    test('escapes attribute values', () {
      expect(project.buildInfo['activities'],
          [contains('"Tom &amp; &quot;Jerry&quot; &lt;3"')]);
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

  test('desugars AARs again only when the dependencies change', () async {
    final project = await createProject('cached_aar_ext');
    project.addDependencies(['androidx.core:core-ktx:1.5.0']);
    final desugared = project.file(
        '.rush/build/files/desugared-aars/androidx.core-core-ktx-1.5.0.aar.jar');

    expect((await project.build()).exitCode, 0);
    final firstBuild = desugared.lastModifiedSync();
    expect((await project.build()).exitCode, 0);
    expect(desugared.lastModifiedSync(), firstBuild);

    project.addDependencies(['com.google.code.gson:gson:2.8.9']);
    final result = await project.build();
    expect(result.exitCode, 0, reason: result.output);
    expect(desugared.lastModifiedSync(), isNot(firstBuild));
  });

  group('resources', () {
    const usesResources = '''
  @SimpleFunction
  public String Title() {
    return form.getString(R.string.com_example_resext_title)
        + R.layout.com_example_resext_card + R.id.title;
  }
''';

    void writeResources(TestProject project) {
      project.file('res/values/strings.xml')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
<resources>
    <string name="com_example_resext_title">Hello</string>
</resources>
''');
      project.file('res/layout/com_example_resext_card.xml')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
<TextView xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/title"
    android:layout_width="wrap_content"
    android:layout_height="wrap_content"
    android:text="@string/com_example_resext_title" />
''');
    }

    test('ship in an AAR named after the extension package', () async {
      final project = await createProject('res_ext', language: 'java');
      writeResources(project);
      final result = await _buildWithFunctions(project, usesResources);
      expect(result.exitCode, 0, reason: result.output);

      expect(project.libraries, contains('com.example.resext.aar'));
      final aar = project.bundledAar('com.example.resext.aar');
      expect(utf8.decode(aar.findFile('AndroidManifest.xml')!.content),
          contains('package="com.example.resext"'));
      expect(
          utf8.decode(aar.findFile('R.txt')!.content),
          allOf(
            contains('int string com_example_resext_title'),
            contains('int layout com_example_resext_card'),
            contains('int id title'),
          ));
      expect(aar.findFile('res/layout/com_example_resext_card.xml'), isNotNull);
      expect(
          project.runtimeClasses
              .where((c) => c.contains('/R\$') || c.endsWith('/R.class')),
          isEmpty);
    });

    test('must be prefixed with the extension package', () async {
      final project = await createProject('res_ext', language: 'java');
      writeResources(project);
      project.file('res/values/greetings.xml').writeAsStringSync('''
<resources>
    <string name="greeting">Hi</string>
</resources>
''');
      final result = await project.build();
      expect(result.exitCode, isNot(0));
      expect(
          result.output,
          contains(
              'string/greeting must be named com_example_resext_greeting'));
      expect(result.output, isNot(contains('Exception')));
    });

    test('report errors at the resource file', () async {
      final project = await createProject('res_ext', language: 'java');
      writeResources(project);
      final layout = project.file('res/layout/com_example_resext_card.xml');
      layout.writeAsStringSync(layout
          .readAsStringSync()
          .replaceFirst('@string/com_example_resext_title', '@string/missing'));
      final result = await project.build();
      expect(result.exitCode, isNot(0));
      expect(
          result.output,
          allOf(
              contains('com_example_resext_card.xml:'), contains('not found')));
    });

    test('are available to Kotlin and optimized builds', () async {
      final project = await createProject('res_ext');
      writeResources(project);
      project.source('${project.className}.kt').writeAsStringSync(_fill('''
package {package}

import com.google.appinventor.components.annotations.Extension
import com.google.appinventor.components.annotations.SimpleFunction
import com.google.appinventor.components.runtime.AndroidNonvisibleComponent
import com.google.appinventor.components.runtime.ComponentContainer

@Extension(description = "Test extension", icon = "icon.png")
class {className}(container: ComponentContainer) : AndroidNonvisibleComponent(container.`\$form`()) {
    @SimpleFunction
    fun Title(): String = form.getString(R.string.com_example_resext_title)
}
''', project));
      final result = await project.build(['--optimize']);
      expect(result.exitCode, 0, reason: result.output);
      expect(project.libraries, contains('com.example.resext.aar'));
    });
  });

  group('core library', () {
    const usesJavaTime = '''
  @SimpleFunction
  public String Tomorrow() {
    return java.time.LocalDate.of(2026, 10, 12).plusDays(1).toString();
  }
''';

    test('is backported from API 24 and only when used', () async {
      final project = await createProject('time_ext', language: 'java');
      project.setMinSdk(24);
      final unused = await _buildWithFunctions(project, '');
      expect(unused.exitCode, 0, reason: unused.output);
      expect(project.runtimeClasses.where((c) => c.contains(r'j$/')), isEmpty);

      final used = await _buildWithFunctions(project, usesJavaTime);
      expect(used.exitCode, 0, reason: used.output);
      final backport = project.runtimeClasses
          .where((c) => c.startsWith('${project.packagePath}/repacked/j\$/'));
      expect(backport,
          contains('${project.packagePath}/repacked/j\$/time/LocalDate.class'));
      expect(backport.length, lessThan(200));
      expect(
          project.runtimeClasses
              .where((c) => c.startsWith(r'j$/') || c.startsWith('java/')),
          isEmpty);
    });

    test('is backported in optimized Kotlin builds', () async {
      final project = await createProject('kotlin_time_ext');
      project.setMinSdk(24);
      project.source('${project.className}.kt').writeAsStringSync(_fill('''
package {package}

import com.google.appinventor.components.annotations.Extension
import com.google.appinventor.components.annotations.SimpleFunction
import com.google.appinventor.components.runtime.AndroidNonvisibleComponent
import com.google.appinventor.components.runtime.ComponentContainer
import java.time.LocalDate

@Extension(description = "Test extension", icon = "icon.png")
class {className}(container: ComponentContainer) : AndroidNonvisibleComponent(container.`\$form`()) {
    @SimpleFunction
    fun Tomorrow(): String = "\${LocalDate.of(2026, 10, 12).plusDays(1)} \${listOf(3, 1, 2).sorted()}"
}
''', project));
      final result = await project.build(['--optimize']);
      expect(result.exitCode, 0, reason: result.output);
      expect(project.runtimeClasses,
          contains('${project.packagePath}/repacked/j\$/time/LocalDate.class'));
    });

    test('is not backported below API 24', () async {
      final project = await createProject('old_time_ext', language: 'java');
      final result = await _buildWithFunctions(project, usesJavaTime);
      expect(result.exitCode, 0, reason: result.output);
      expect(project.runtimeClasses.where((c) => c.contains(r'j$/')), isEmpty);
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

    test('keep what their ProGuard rules keep', () async {
      final project = await createProject('rules_ext', language: 'java');
      project.addDependencies(['com.google.code.gson:gson:2.8.9']);
      final parser =
          '${project.packagePath}/repacked/com/google/gson/JsonParser.class';
      final unruled = await project.build();
      expect(unruled.exitCode, 0, reason: unruled.output);
      expect(project.runtimeClasses, isNot(contains(parser)));

      final rules = Archive()
        ..addFile(ArchiveFile.string('META-INF/proguard/keep.pro',
            '-keep class com.google.gson.JsonParser'));
      project
          .file('deps/keep-rules.jar')
          .writeAsBytesSync(ZipEncoder().encode(rules));
      project.addDependencies(['keep-rules.jar']);
      final ruled = await project.build();
      expect(ruled.exitCode, 0, reason: ruled.output);
      expect(project.runtimeClasses, contains(parser));
    });

    test('ship as AARs when a bundled AAR depends on them', () async {
      final project = await createProject('media_ext', language: 'java');
      project.addDependencies(['androidx.media3:media3-common:1.11.1']);
      project.setMinSdk(23);
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

  test('warns when the same AAR is both local and remote', () async {
    final project = await createProject('duplicate_aar_ext');
    project.addDependencies(['androidx.core:core-ktx:1.5.0']);
    final remote = await project.build();
    expect(remote.exitCode, 0, reason: remote.output);
    final localAar = project.file('deps/core-ktx-local.aar');
    localAar.writeAsBytesSync(ZipEncoder()
        .encode(project.bundledAar('androidx.core-core-ktx-1.5.0.aar')));
    project.addDependencies(['core-ktx-local.aar']);

    final result = await project.build();
    expect(result.exitCode, 0, reason: result.output);
    expect(
        result.output,
        contains(
            'androidx.core:core-ktx:1.5.0 and core-ktx-local.aar are the same library'));
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

    test('keeps ProGuard notes out of the output', () async {
      final project = await createProject('quiet_ext');
      final result = await project.build(['--optimize']);
      expect(result.exitCode, 0, reason: result.output);
      expect(result.output, isNot(contains('ProGuard, version')));
      expect(result.output, isNot(contains('proguard/manual')));
    });
  });

  group('migrate', () {
    late Directory project;

    setUp(() async {
      project = await Directory.systemTemp.createTemp('rush-legacy-');
      final files = {
        'rush.yml': '''
name: Legacy
description: Says "hi" for \$5.
homepage: https://example.com/legacy
license: https://example.com/legacy/LICENSE
min_sdk: 21
version:
  number: auto
  name: '1.2.0'
authors:
  - Jane Doe
build:
  desugar:
    enable: true
  kotlin:
    enable: true
assets:
  icon: icon.png
''',
        'src/AndroidManifest.xml': '''
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.example.legacy">
    <application></application>
</manifest>
''',
        'src/com/example/legacy/Legacy.kt': r'''
package com.example.legacy

import com.google.appinventor.components.annotations.SimpleFunction
import com.google.appinventor.components.runtime.AndroidNonvisibleComponent
import com.google.appinventor.components.runtime.ComponentContainer

class Legacy(container: ComponentContainer) : AndroidNonvisibleComponent(container.`$form`()) {
    @SimpleFunction(description = "Greets")
    fun Greet(): String = "hi"
}
''',
        'assets/icon.png': 'icon',
      };
      for (final entry in files.entries) {
        File('${project.path}/${entry.key}')
          ..createSync(recursive: true)
          ..writeAsStringSync(entry.value.trimLeft());
      }
      Directory('${project.path}/.rush').createSync();
    });

    tearDown(() => project.delete(recursive: true));

    test('writes a config the new version builds with', () async {
      final migrated = await rush(['migrate'], workingDirectory: project.path);
      expect(migrated.exitCode, 0, reason: migrated.output);

      final config = File('${project.path}/rush.yml').readAsStringSync();
      expect(
          config,
          allOf(
            contains('homepage: https://example.com/legacy'),
            contains('license: https://example.com/legacy/LICENSE'),
            isNot(contains('desugar')),
            isNot(contains('authors')),
          ));

      final built = await rush(['build'], workingDirectory: project.path);
      expect(built.exitCode, 0, reason: built.output);
    });

    Future<ProcessResult> migrateWithVersionNumber(String number) {
      final config = File('${project.path}/rush.yml');
      config.writeAsStringSync(config.readAsStringSync().replaceFirst(
          RegExp(r'  number: .*\n  name: .*\n'), '  number: $number\n'));
      return rush(['migrate'], workingDirectory: project.path);
    }

    test('uses the version number when there is no version name', () async {
      final migrated = await migrateWithVersionNumber('3');
      expect(migrated.exitCode, 0, reason: migrated.output);
      expect(File('${project.path}/rush.yml').readAsStringSync(),
          contains("version: '3'"));
    });

    test('starts at 1.0.0 when the version number was automatic', () async {
      final migrated = await migrateWithVersionNumber('auto');
      expect(migrated.exitCode, 0, reason: migrated.output);
      expect(migrated.output, contains("version: '1.0.0'"));
      expect(File('${project.path}/rush.yml').readAsStringSync(),
          contains("version: '1.0.0'"));
    });

    test('keeps unlisted local libraries for compilation only', () async {
      final classes = Directory('${project.path}/lib-classes');
      File('${project.path}/Greeting.java').writeAsStringSync(
          'package com.example.lib; public class Greeting { public static String text() { return "hi"; } }');
      final javac = await Process.run(
          'javac', ['-d', classes.path, '${project.path}/Greeting.java']);
      expect(javac.exitCode, 0, reason: '${javac.stderr}');
      final greeting = File('${classes.path}/com/example/lib/Greeting.class');
      File('${project.path}/deps/greeting.jar')
        ..createSync(recursive: true)
        ..writeAsBytesSync(ZipEncoder().encode(Archive()
          ..addFile(ArchiveFile('com/example/lib/Greeting.class',
              greeting.lengthSync(), greeting.readAsBytesSync()))));
      final source = File('${project.path}/src/com/example/legacy/Legacy.kt');
      source.writeAsStringSync(source
          .readAsStringSync()
          .replaceFirst('= "hi"', '= com.example.lib.Greeting.text()'));

      final migrated = await rush(['migrate'], workingDirectory: project.path);
      expect(migrated.exitCode, 0, reason: migrated.output);
      expect(File('${project.path}/rush.yml').readAsStringSync(),
          contains('provided_dependencies:\n- greeting.jar'));

      final built = await rush(['build'], workingDirectory: project.path);
      expect(built.exitCode, 0, reason: built.output);
    });
  });

  test('new projects target Android 5.0 (API 21)', () async {
    final project = await createProject('template_ext', language: 'java');
    expect(
        project.file('rush.yml').readAsStringSync(), contains('min_sdk: 21'));
  });
}
