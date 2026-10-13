import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:rush/src/commands/build/fixes/raw_fonts.dart';
import 'package:test/test.dart';

const _font = [0, 1, 0, 0, 0, 16];

Archive _archive(Map<String, Object> files) {
  final archive = Archive();
  for (final MapEntry(key: name, value: content) in files.entries) {
    archive.add(content is String
        ? ArchiveFile.string(name, content)
        : ArchiveFile.bytes(name, content as List<int>));
  }
  return archive;
}

String _manifest(String package) =>
    '<manifest xmlns:android="http://schemas.android.com/apk/res/android" '
    'package="$package"/>';

Set<String> _names(Archive archive) => {
      for (final file in archive.files) file.name,
    };

String _text(Archive archive, String name) =>
    utf8.decode(archive.findFile(name)!.content);

void main() {
  final ui = _archive({
    'AndroidManifest.xml': _manifest('androidx.media3.ui'),
    'R.txt': 'int attr font 0x7f010001\n'
        'int font roboto 0x7f020001\n'
        'int font family 0x7f020002\n'
        'int[] styleable FontFamilyFont { 0x7f010001 }\n',
    'res/font/roboto.ttf': _font,
    'res/font-v26/family.xml':
        '<font-family><font android:font="@font/roboto"/></font-family>',
    'res/values/styles.xml': '<style><item name="android:fontFamily">'
        '@androidx.media3.ui:font/roboto</item></style>',
    'res/layout/label.xml': '<TextView android:fontFamily="@font/family"/>',
  });

  test('moves binary fonts to res/raw and XML families to res/xml', () {
    final fixed = moveFontsToRaw({'ui.aar': ui}).libraries['ui.aar']!;
    expect(_names(fixed),
        containsAll(['res/raw/roboto.ttf', 'res/xml-v26/family.xml']));
    expect(_names(fixed).where((el) => el.startsWith('res/font')), isEmpty);
    expect(fixed.findFile('res/raw/roboto.ttf')!.content, _font);
  });

  test('retypes font rows and leaves the font attribute alone', () {
    final fixed = moveFontsToRaw({'ui.aar': ui}).libraries['ui.aar']!;
    expect(
        _text(fixed, 'R.txt'),
        'int attr font 0x7f010001\n'
        'int raw roboto 0x7f020001\n'
        'int xml family 0x7f020002\n'
        'int[] styleable FontFamilyFont { 0x7f010001 }\n');
  });

  test('rewrites font references in every XML of every library', () {
    final dependent = _archive({
      'AndroidManifest.xml': '<manifest package="com.example.player">'
          '<meta-data android:resource="@font/roboto"/></manifest>',
      'res/values/themes.xml': '<item>@font/roboto</item>',
    });
    final result = moveFontsToRaw({'ui.aar': ui, 'player.aar': dependent});
    final fixed = result.libraries['ui.aar']!;
    expect(_text(fixed, 'res/xml-v26/family.xml'), contains('@raw/roboto'));
    expect(_text(fixed, 'res/values/styles.xml'),
        contains('@androidx.media3.ui:raw/roboto'));
    expect(_text(fixed, 'res/layout/label.xml'), contains('@xml/family'));
    expect(_text(result.libraries['player.aar']!, 'res/values/themes.xml'),
        '<item>@raw/roboto</item>');
    expect(_text(result.libraries['player.aar']!, 'AndroidManifest.xml'),
        contains('android:resource="@raw/roboto"'));
  });

  test('describes a shim that keeps R.font working', () {
    final shim = moveFontsToRaw({'ui.aar': ui}).shims['ui.aar']!;
    expect(shim.package, 'androidx.media3.ui');
    expect(shim.kinds, {'roboto': 'raw', 'family': 'xml'});
    expect(
        shim.source,
        allOf(
          startsWith('package androidx.media3.ui;'),
          contains('public static int roboto = raw.roboto;'),
          contains('public static int family = xml.family;'),
        ));
  });

  test('fails when a moved font would replace a raw resource', () {
    final clashing = _archive({
      'AndroidManifest.xml': _manifest('com.example.sounds'),
      'res/raw/roboto.mp3': [1, 2, 3],
    });
    expect(
        () => moveFontsToRaw({'ui.aar': ui, 'sounds.aar': clashing}),
        throwsA(isA<Exception>().having((e) => '$e', 'message',
            contains('res/raw/roboto.mp3 in sounds.aar'))));
  });

  test('leaves libraries without fonts untouched', () {
    final plain = _archive({
      'AndroidManifest.xml': _manifest('com.example.plain'),
      'res/values/strings.xml': '<string name="font">font/roboto</string>',
    });
    expect(moveFontsToRaw({'plain.aar': plain}).libraries, isEmpty);
    expect(moveFontsToRaw({'ui.aar': ui, 'plain.aar': plain}).libraries.keys,
        ['ui.aar']);
  });

  test('passes an already fixed library through unchanged', () {
    final fixed = moveFontsToRaw({'ui.aar': ui}).libraries['ui.aar']!;
    final again = moveFontsToRaw({'ui.aar': fixed});
    expect(again.libraries, isEmpty);
    expect(again.shims, isEmpty);
  });
}
