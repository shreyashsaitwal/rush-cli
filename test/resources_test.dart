@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';

import 'package:test/test.dart';

import 'support/fixtures.dart';
import 'support/project.dart';

const _usesResources = '''
  @SimpleFunction
  public String Title() {
    return form.getString(R.string.com_example_resext_title)
        + R.layout.com_example_resext_card + R.id.title;
  }
''';

void _writeResources(TestProject project) {
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

void main() {
  test('resources ship in an AAR named after the extension package', () async {
    final project = await TestProject.create('res_ext');
    _writeResources(project);
    project.writeJavaExtension(_usesResources);
    final result = await project.build();
    expect(result.exitCode, 0, reason: result.output);

    final aix = project.aix;
    expect(aix.libraries, contains('com.example.resext.aar'));
    final aar = aix.library('com.example.resext.aar');
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
        aix.classNames
            .where((c) => c.contains('/R\$') || c.endsWith('/R.class')),
        isEmpty);
  });

  test('resources must be prefixed with the extension package', () async {
    final project = await TestProject.create('res_ext');
    _writeResources(project);
    project.file('res/values/greetings.xml').writeAsStringSync('''
<resources>
    <string name="greeting">Hi</string>
</resources>
''');
    final result = await project.build();
    expect(result.exitCode, isNot(0));
    expect(result.output,
        contains('string/greeting must be named com_example_resext_greeting'));
    expect(result.output, isNot(contains('Exception')));
  });

  test('resource errors point at the resource file', () async {
    final project = await TestProject.create('res_ext');
    _writeResources(project);
    final layout = project.file('res/layout/com_example_resext_card.xml');
    layout.writeAsStringSync(layout
        .readAsStringSync()
        .replaceFirst('@string/com_example_resext_title', '@string/missing'));
    final result = await project.build();
    expect(result.exitCode, isNot(0));
    expect(result.output,
        allOf(contains('com_example_resext_card.xml:'), contains('not found')));
  });

  test('resources are available to Kotlin and optimized builds', () async {
    final project = await TestProject.create('res_ext', language: 'kotlin');
    _writeResources(project);
    project.writeSource('${project.className}.kt', '''
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
''');
    final result = await project.build(['--optimize']);
    expect(result.exitCode, 0, reason: result.output);
    expect(project.aix.libraries, contains('com.example.resext.aar'));
  });
}
