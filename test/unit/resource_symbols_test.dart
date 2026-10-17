import 'package:archive/archive.dart';
import 'package:rush/src/commands/build/resource_names.dart';
import 'package:rush/src/commands/build/resource_symbols.dart';
import 'package:test/test.dart';

Archive _aar(Map<String, String> files) {
  final archive = Archive();
  for (final MapEntry(key: name, value: content) in files.entries) {
    archive.add(ArchiveFile.string(name, content));
  }
  return archive;
}

final _library = _aar({
  'AndroidManifest.xml': '<manifest package="lib.ui"/>',
  'res/layout/player.xml': '<FrameLayout '
      'xmlns:android="http://schemas.android.com/apk/res/android">'
      '<View android:id="@+id/play_button"/></FrameLayout>',
  'res/drawable-v21/play.xml': '<vector/>',
  'res/values/values.xml': '<resources>'
      '<string name="title">Title</string>'
      '<style name="Lib.Theme" parent="Theme.AppCompat">'
      '<item name="libSize">1dp</item></style>'
      '<attr name="libSize" format="dimension"/>'
      '<declare-styleable name="Box"><attr name="libMode">'
      '<enum name="fast" value="1"/></attr>'
      '<attr name="android:text"/></declare-styleable>'
      '<item type="id" name="anchor"/>'
      '</resources>',
});

final _extension = _aar({
  'res/layout/com_example_ext_card.xml': '<FrameLayout '
      'xmlns:android="http://schemas.android.com/apk/res/android">'
      '<View android:id="@+id/com_example_ext_title"/></FrameLayout>',
  'res/values/values.xml': '<resources>'
      '<style name="com_example_ext_theme" parent="Lib.Theme"/>'
      '<declare-styleable name="com_example_ext_Box">'
      '<attr name="com_example_ext_size" format="dimension"/>'
      '<attr name="libSize"/></declare-styleable>'
      '</resources>',
});

const _linked = '''
int attr com_example_ext_size 0x00000000
int attr libMode 0x00000000
int attr libSize 0x00000000
int drawable play 0x00000000
int id com_example_ext_title 0x00000000
int id fast 0x00000000
int id play_button 0x00000000
int layout com_example_ext_card 0x00000000
int layout player 0x00000000
int style Lib_Theme 0x00000000
int style com_example_ext_theme 0x00000000
int[] styleable com_example_ext_Box { 0x00000000, 0x00000000 }
int styleable com_example_ext_Box_com_example_ext_size 0
int styleable com_example_ext_Box_libSize 1
''';

void main() {
  test('stubs the resources libraries define, attributes as defined', () {
    expect(
        ResourceDefinitions.of([_library]).stubs,
        '<resources>'
        '<attr name="libMode"><enum name="fast" value="1"/></attr>'
        '<attr name="libSize" format="dimension"/>'
        '<item type="drawable" name="play">@null</item>'
        '<item type="id" name="anchor"/>'
        '<item type="id" name="play_button"/>'
        '<item type="layout" name="player">@null</item>'
        '<item type="string" name="title">@null</item>'
        '<style name="Lib.Theme" parent=""/>'
        '</resources>');
  });

  test('keeps only the symbols the extension defines', () {
    expect(
        ownSymbols(_linked, ResourceDefinitions.of([_extension])),
        'int attr com_example_ext_size 0x00000000\n'
        'int id com_example_ext_title 0x00000000\n'
        'int layout com_example_ext_card 0x00000000\n'
        'int style com_example_ext_theme 0x00000000\n'
        'int[] styleable com_example_ext_Box { 0x00000000, 0x00000000 }\n'
        'int styleable com_example_ext_Box_com_example_ext_size 0\n'
        'int styleable com_example_ext_Box_libSize 1\n');
  });

  test('writes the R class of the symbols', () {
    expect(
        rClass(
            'com.example.ext',
            'int attr com_example_ext_size 0x00000000\n'
                'int id com_example_ext_title 0x00000000\n'
                'int[] styleable com_example_ext_Box { 0x0101014f, 0x00000000 }\n'
                'int styleable com_example_ext_Box_android_text 0\n'
                'int styleable com_example_ext_Box_com_example_ext_size 1\n'),
        'package com.example.ext;\n'
        '\n'
        'public final class R {\n'
        '  public static final class attr {\n'
        '    public static int com_example_ext_size=0x00000000;\n'
        '  }\n'
        '  public static final class id {\n'
        '    public static int com_example_ext_title=0x00000000;\n'
        '  }\n'
        '  public static final class styleable {\n'
        '    public static final int[] com_example_ext_Box={\n'
        '      0x0101014f, 0x00000000\n'
        '    };\n'
        '    public static int com_example_ext_Box_android_text=0;\n'
        '    public static int com_example_ext_Box_com_example_ext_size=1;\n'
        '  }\n'
        '}\n');
  });

  test('combines the definitions of several sources', () {
    final combined = ResourceDefinitions.of([_library]) +
        ResourceDefinitions.of([_extension]);

    expect(
        combined.defined,
        containsAll(
            [('drawable', 'play'), ('layout', 'com_example_ext_card')]));
    expect(
        combined.stubs, contains('<attr name="libSize" format="dimension"/>'));
  });
}
