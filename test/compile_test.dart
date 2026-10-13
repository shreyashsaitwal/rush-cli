@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:rush/src/utils/constants.dart';
import 'package:test/test.dart';

import 'support/aix.dart';
import 'support/fixtures.dart';
import 'support/project.dart';

const _kotlinExtension = '''
package {package}

import {package}.helpers.Mode
import com.google.appinventor.components.annotations.DesignerProperty
import com.google.appinventor.components.annotations.Extension
import com.google.appinventor.components.annotations.Options
import com.google.appinventor.components.annotations.PropertyCategory
import com.google.appinventor.components.annotations.SimpleFunction
import com.google.appinventor.components.annotations.SimpleProperty
import com.google.appinventor.components.common.PropertyTypeConstants
import com.google.appinventor.components.runtime.AndroidNonvisibleComponent
import com.google.appinventor.components.runtime.ComponentContainer

@Extension(description = "Test extension", icon = "icon.png")
class {className}(container: ComponentContainer) : AndroidNonvisibleComponent(container.`\$form`()) {
    private var speed = 1

    @SimpleFunction(description = "Moves")
    fun Move(mode: Mode) {}

    @SimpleProperty(description = "Mode")
    @Options(Mode::class)
    fun CurrentMode(): String = "fast"

    @SimpleProperty(description = "Speed", category = PropertyCategory.APPEARANCE)
    fun Speed(): Int = speed

    @DesignerProperty(editorType = PropertyTypeConstants.PROPERTY_TYPE_NON_NEGATIVE_INTEGER, defaultValue = "1")
    @SimpleProperty
    fun Speed(value: Int) {
        speed = value
    }
}
''';

const _javaBlocks = '''
  record Point(int x, int y) {}

  @SimpleFunction(description = "Waits")
  public void Wait(int millis, Continuation<Void> done) {
    done.call(null);
  }

  @SimpleFunction(description = "Fetches")
  public void Fetch(String url, Continuation<String> result) {
    result.call(url);
  }

  @SimpleFunction(description = "Counts")
  public void Count(Continuation<Integer> result) {
    result.call(1);
  }

  @SimpleFunction(description = "Checks")
  public void Check(Continuation<Boolean> result) {
    result.call(true);
  }

  @SimpleFunction(description = "Moves")
  public void Move({package}.helpers.Mode mode) {
  }

  @com.google.appinventor.components.annotations.SimpleProperty(description = "Mode")
  @com.google.appinventor.components.annotations.Options({package}.helpers.Mode.class)
  public String CurrentMode() {
    return "fast";
  }

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

const _manifest = '''
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="{package}">
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28"/>
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation"/>
    <uses-feature android:name="android.hardware.camera" android:required="false"/>
    <application>
        <meta-data android:name="greeting" android:value="Tom &amp; &quot;Jerry&quot; &lt;3"/>
    </application>
</manifest>
''';

Map<String, dynamic> _named(
        Map<String, dynamic> component, String key, String name) =>
    (component[key] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((m) => m['name'] == name);

void main() {
  group('a Kotlin extension with Java helpers in a path with spaces', () {
    late TestProject project;
    late Aix aix;

    setUpAll(() async {
      project = await TestProject.create('mixed_ext',
          language: 'kotlin', parentPrefix: 'rush test with spaces ');
      project.writeHelperEnum();
      project.writeSource('${project.className}.kt', _kotlinExtension);
      final result = await project.build();
      if (result.exitCode != 0) fail(result.output);
      aix = project.aix;
    });

    test('keeps the Kotlin classes and the Java helpers', () {
      expect(
          aix.classNames,
          containsAll([
            project.classFile(project.className),
            project.classFile('helpers/Mode')
          ]));
    });

    test('does not mark designer properties as always sent', () {
      final property =
          (aix.component['properties'] as List).cast<Map<String, dynamic>>();
      expect(property.single['alwaysSend'], anyOf(isNull, isFalse));
    });

    test('puts properties in their category', () {
      expect(_named(aix.component, 'blockProperties', 'Speed')['category'],
          'Appearance');
    });

    test('lists a property with a getter and setter once', () {
      final names = (aix.component['blockProperties'] as List)
          .map((p) => p['name'])
          .toList();
      expect(names, unorderedEquals(['Speed', 'CurrentMode']));
    });

    test('honors @Options on Kotlin getters', () {
      expect(
          _named(aix.component, 'blockProperties', 'CurrentMode')['helper']
              ?['data']?['className'],
          '${project.package}.helpers.Mode');
    });

    test('recompiles helpers after the build directory is deleted', () async {
      Directory('${project.dir.path}/.rush/build').deleteSync(recursive: true);
      final result = await project.build();
      expect(result.exitCode, 0, reason: result.output);
    });
  });

  group('a Java extension', () {
    late TestProject project;
    late Aix aix;

    setUpAll(() async {
      project = await TestProject.create('blocks_ext');
      project.writeHelperEnum();
      project.writeJavaExtension(_javaBlocks);
      project.editSource(
          '${project.className}.java', RegExp(r',\s*icon = "icon.png"'), '');
      final result = await project.build();
      if (result.exitCode != 0) fail(result.output);
      aix = project.aix;
    });

    test('makes functions with a continuation asynchronous', () {
      final wait = _named(aix.component, 'methods', 'Wait');
      final fetch = _named(aix.component, 'methods', 'Fetch');
      expect(wait, containsPair('continuation', true));
      expect(wait, isNot(contains('returnType')));
      expect(wait['params'], [
        {'name': 'millis', 'type': 'number'}
      ]);
      expect(fetch, containsPair('continuation', true));
      expect(fetch, containsPair('returnType', 'text'));
    });

    test('gives continuations of boxed types block result types', () {
      expect(_named(aix.component, 'methods', 'Count')['returnType'], 'number');
      expect(
          _named(aix.component, 'methods', 'Check')['returnType'], 'boolean');
    });

    test('describes dropdown options and honors @Options on getters', () {
      final options = _named(aix.component, 'methods', 'Move')['params'][0]
          ['helper']['data']['options'] as List;
      expect(options.map((o) => o['description']),
          ['Moves quickly.', 'Moves carefully.']);
      expect(
          _named(aix.component, 'blockProperties', 'CurrentMode')['helper']
              ?['data']?['className'],
          '${project.package}.helpers.Mode');
    });

    test('compiles Java 17 language features', () {
      expect(
          aix.classNames,
          contains(
              '${project.packagePath}/repacked/com/android/tools/r8/RecordTag.class'));
      expect(
          aix.classNames.where((c) => c.startsWith('com/android/')), isEmpty);
    });

    test('uses the default icon when none is set', () {
      expect(aix.component['iconName'], 'images/extension.png');
    });
  });

  group('a documented extension', () {
    late TestProject project;
    late ProcessResult build;
    late Aix aix;

    setUpAll(() async {
      project = await TestProject.create('docs_ext');
      project.writeSource('${project.className}.java', _documentedExtension);
      project.writeHelperEnum();
      project.file('assets/data.txt').writeAsStringSync('data');
      project.file('LICENSE.txt').writeAsStringSync('MIT');
      project
          .file('src/AndroidManifest.xml')
          .writeAsStringSync(project.fill(_manifest));
      project.file('rush.yml').writeAsStringSync('''
version: '2.3.0'
min_sdk: 24
homepage: https://example.com/ext
license: LICENSE.txt
assets:
- data.txt
''');
      build = await project.build();
      if (build.exitCode != 0) fail(build.output);
      aix = project.aix;
    });

    test('is described in Markdown next to the AIX', () {
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

    test('takes metadata from rush.yml', () {
      expect(
          aix.component,
          allOf(
            containsPair('versionName', '2.3.0'),
            containsPair('helpUrl', 'https://example.com/ext'),
            containsPair('androidMinSdk', '24'),
          ));
      expect(aix.buildInfo['assets'], ['data.txt']);
      expect(aix.buildInfo['androidMinSdk'], ['24']);
    });

    test('links the license file', () {
      expect(aix.component['licenseName'], 'aiwebres/LICENSE');
      expect(aix, ships('aiwebres/LICENSE'));
    });

    test('keeps manifest permission constraints', () {
      expect(aix.buildInfo['permissionConstraints'], {
        'android.permission.READ_EXTERNAL_STORAGE': {'maxSdkVersion': 32},
        'android.permission.BLUETOOTH_SCAN': {
          'usesPermissionFlags': 'neverForLocation'
        },
      });
    });

    test('leaves the storage write limit to App Inventor', () {
      expect(build.output, contains('WRITE_EXTERNAL_STORAGE'));
    });

    test('keeps manifest features', () {
      expect(aix.buildInfo['features'], [
        allOf(contains('android:name="android.hardware.camera"'),
            contains('android:required="false"'))
      ]);
    });

    test('escapes manifest attribute values', () {
      expect(aix.buildInfo['activities'],
          [contains('"Tom &amp; &quot;Jerry&quot; &lt;3"')]);
    });
  });

  group('a rebuilt project', () {
    const skippedCompile = 'skipped the compile step';
    const skippedDex = 'skipped the dex step';
    late TestProject project;

    Future<String> build() async {
      final result = await project.build();
      expect(result.exitCode, 0, reason: result.output);
      return result.output;
    }

    setUpAll(() async {
      project = await TestProject.create('rebuild_ext');
      await build();
    });

    test('skips compiling and dexing when nothing changed', () async {
      expect(
          await build(), allOf(contains(skippedCompile), contains(skippedDex)));
    });

    test('ships the same AIX as a clean build', () async {
      await build();
      expect(await build(), contains(skippedCompile));
      final rebuilt = project.aixFile.readAsBytesSync();
      await rush(['clean'], workingDirectory: project.dir.path);
      expect(await build(), isNot(contains(skippedCompile)));
      expect(project.aixFile.readAsBytesSync(), rebuilt);
    });

    test('compiles again when a source changes', () async {
      project.writeJavaExtension('''
  @SimpleFunction
  public int Answer() {
    return 42;
  }
''');
      expect(await build(),
          allOf(isNot(contains(skippedCompile)), isNot(contains(skippedDex))));
      expect((project.aix.component['methods'] as List).map((m) => m['name']),
          contains('Answer'));
    });

    test('compiles again when a dependency changes', () async {
      project.addDependencies(['com.google.code.gson:gson:2.8.9']);
      expect(await build(), isNot(contains(skippedCompile)));
    });

    test('compiles again when its classes are deleted', () async {
      await build();
      Directory('${project.dir.path}/.rush/build/classes')
          .deleteSync(recursive: true);
      expect(await build(), isNot(contains(skippedCompile)));
      expect(project.aix.classNames,
          contains(project.classFile(project.className)));
    });
  });

  test('removes classes of deleted helpers', () async {
    final project = await TestProject.create('helper_ext');
    project.writeHelperEnum();
    expect((await project.build()).exitCode, 0);
    expect(project.aix.classNames, contains(project.classFile('helpers/Mode')));

    project.source('helpers/Mode.java').deleteSync();
    final result = await project.build();
    expect(result.exitCode, 0, reason: result.output);
    expect(project.aix.classNames,
        isNot(contains(project.classFile('helpers/Mode'))));
  });

  test('runs in two projects at the same time', () async {
    final first = await TestProject.create('first_ext');
    final second = await TestProject.create('second_ext');
    final results = await Future.wait([first.build(), second.build()]);
    for (final result in results) {
      expect(result.exitCode, 0, reason: result.output);
    }
  });

  group('errors', () {
    test('name the processor option the build left out', () async {
      final project = await TestProject.create('no_options_ext');
      final home = Platform.environment['RUSH_HOME']!;
      final result = await Process.run('javac', [
        '-proc:only',
        ...['-processorpath', p.join(home, 'libs', 'processor.jar')],
        ...[
          '-cp',
          [
            p.join(home, 'libs', 'annotations.jar'),
            p.join(home, 'ai2', ai2Version, 'libs', 'AndroidRuntime.jar'),
          ].join(Platform.isWindows ? ';' : ':'),
        ],
        project.source('${project.className}.java').path,
      ]);
      expect(result.exitCode, isNot(0));
      expect(result.output,
          contains('Missing annotation processor option -Arush.options'));
    });

    test('explain that dropdown enums belong in a helpers directory', () async {
      final project = await TestProject.create('misplaced_ext');
      project.source('options/Mode.java')
        ..createSync(recursive: true)
        ..writeAsStringSync(
            project.helperEnum.replaceFirst('.helpers;', '.options;'));
      project.writeJavaExtension('''
  @SimpleFunction(description = "Moves")
  public void Move(${project.package}.options.Mode mode) {
  }
''');
      final result = await project.build();
      expect(result.exitCode, 1, reason: result.output);
      expect(
          result.output,
          contains('Dropdown enum ${project.package}.options.Mode must be in '
              'a directory named `helpers`'));
    });

    test('reject types App Inventor has no block for', () async {
      final project = await TestProject.create('types_ext');
      project.writeJavaExtension('''
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
      final result = await project.build();
      expect(result.exitCode, isNot(0));
      expect(result.output, contains("'java.util.Date'"));
      expect(result.output, contains("'char'"));
      expect(result.output, contains('use the primitive type int'));
      expect(result.output, isNot(contains('Exception')));
    });

    test('point at the Kotlin source', () async {
      final project =
          await TestProject.create('kotlin_types_ext', language: 'kotlin');
      project.editSource(
          '${project.className}.kt',
          'fun SumAll(listOfInts: YailList)',
          'fun SumAll(listOfInts: YailList, times: Int?)');
      final result = await project.build();
      expect(result.exitCode, isNot(0));
      expect(result.output, contains('${project.className}.kt:'));
      expect(result.output, isNot(contains('kapt')));
    });

    test('require all extensions to share a package', () async {
      final project = await TestProject.create('split_ext');
      project.source('other/Other.java')
        ..createSync(recursive: true)
        ..writeAsStringSync(project
            .javaExtension('')
            .replaceFirst('package ${project.package};',
                'package ${project.package}.other;')
            .replaceAll(project.className, 'Other'));
      final result = await project.build();
      expect(result.exitCode, isNot(0));
      expect(result.output, contains('${project.package}.other'));
      expect(result.output, isNot(contains('Exception')));
    });

    test('name a missing icon file', () async {
      final project = await TestProject.create('missing_icon_ext');
      project.editSource('${project.className}.java', 'icon = "icon.png"',
          'icon = "missing.png"');
      final result = await project.build();
      expect(result.exitCode, isNot(0));
      expect(result.output, contains('missing.png'));
      expect(result.output, isNot(contains('Exception')));
    });
  });
}
