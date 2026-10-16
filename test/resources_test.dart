@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';

import 'package:archive/archive.dart';
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

void _useLibraryResources(TestProject project) {
  project.file('deps/widgets.aar')
    ..createSync(recursive: true)
    ..writeAsBytesSync(ZipEncoder().encode(Archive()
      ..addFile(ArchiveFile.string(
          'AndroidManifest.xml', '<manifest package="com.example.widgets"/>'))
      ..addFile(ArchiveFile.string('res/drawable/play.xml', '<vector/>'))
      ..addFile(ArchiveFile.string(
          'res/values/values.xml',
          '<resources><attr name="widgetSize" format="dimension"/>'
              '<style name="Widget.Theme" parent="Theme.AppCompat">'
              '<item name="widgetSize">4dp</item></style></resources>'))
      ..addFile(ArchiveFile.string('R.txt',
          'int attr widgetSize 0x0\nint drawable play 0x0\nint style Widget_Theme 0x0\n'))
      ..addFile(
          ArchiveFile.bytes('classes.jar', ZipEncoder().encode(Archive())))));
  project.addDependencies(['widgets.aar']);
  project.file('res/layout/com_example_resext_icon.xml')
    ..createSync(recursive: true)
    ..writeAsStringSync('<ImageView '
        'xmlns:android="http://schemas.android.com/apk/res/android" '
        'xmlns:app="http://schemas.android.com/apk/res-auto" '
        'android:layout_width="wrap_content" '
        'android:layout_height="wrap_content" android:src="@drawable/play" '
        'app:widgetSize="2dp"/>');
  project.file('res/values/styles.xml')
    ..createSync(recursive: true)
    ..writeAsStringSync('<resources>'
        '<style name="com_example_resext_theme" parent="Widget.Theme">'
        '<item name="widgetSize">8dp</item></style></resources>');
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

  test('resources can\'t use the prefix of private libraries', () async {
    final project = await TestProject.create('res_ext');
    _writeResources(project);
    project.file('res/values/greetings.xml').writeAsStringSync('''
<resources>
    <string name="com_example_resext_repacked_greeting">Hi</string>
</resources>
''');
    final result = await project.build();
    expect(result.exitCode, isNot(0));
    expect(
        result.output,
        contains('string/com_example_resext_repacked_greeting can\'t start '
            'with com_example_resext_repacked_, which Rush gives the '
            'resources of private libraries'));
  });

  test('resources can reference the resources of shared libraries', () async {
    final project = await TestProject.create('res_ext');
    _useLibraryResources(project);
    project.placeLibraries({'widgets.aar': 'shared'});

    final result = await project.build();
    expect(result.exitCode, 0, reason: result.output);
    final aar = project.aix.library('com.example.resext.aar');
    expect(
        utf8.decode(aar.findFile('R.txt')!.content),
        'int layout com_example_resext_icon 0x00000000\n'
        'int style com_example_resext_theme 0x00000000\n');
    expect(
        utf8.decode(
            aar.findFile('res/layout/com_example_resext_icon.xml')!.content),
        contains('android:src="@drawable/play"'));
  });

  test('resources follow the renamed resources of private libraries', () async {
    final project = await TestProject.create('res_ext');
    _useLibraryResources(project);

    final result = await project.build();
    expect(result.exitCode, 0, reason: result.output);
    const renamed = 'com_example_resext_repacked_';
    final aar = project.aix.library('com.example.resext.aar');
    String text(String name) => utf8.decode(aar.findFile(name)!.content);
    expect(
        text('res/layout/com_example_resext_icon.xml'),
        allOf(contains('android:src="@drawable/${renamed}play"'),
            contains('app:${renamed}widgetSize="2dp"')));
    expect(
        text('res/values/styles.xml'),
        '<resources>'
        '<style name="com_example_resext_theme" '
        'parent="${renamed}Widget.Theme">'
        '<item name="${renamed}widgetSize">8dp</item></style></resources>');
  });

  test('raw resources ship as written, XML or not', () async {
    final project = await TestProject.create('res_ext');
    _writeResources(project);
    _useLibraryResources(project);
    const data = '<key>value without an end';
    project.file('res/raw/com_example_resext_data.xml')
      ..createSync(recursive: true)
      ..writeAsStringSync(data);

    final result = await project.build();
    expect(result.exitCode, 0, reason: result.output);
    expect(
        utf8.decode(project.aix
            .library('com.example.resext.aar')
            .findFile('res/raw/com_example_resext_data.xml')!
            .content),
        data);
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
