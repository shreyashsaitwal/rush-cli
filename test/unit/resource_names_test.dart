import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:rush/src/commands/build/resource_names.dart';
import 'package:test/test.dart';

const _prefix = 'com_example_ext_';
const _manifest = '<manifest package="lib.ui"/>';

Archive _aar(Map<String, String> files) {
  final archive = Archive();
  for (final MapEntry(key: name, value: content) in files.entries) {
    archive.add(ArchiveFile.string(name, content));
  }
  return archive;
}

String _text(Archive archive, String name) =>
    utf8.decode(archive.findFile(name)!.content);

Archive _renamed(Map<String, String> files, [List<Archive> others = const []]) {
  final aar = _aar({'AndroidManifest.xml': _manifest, ...files});
  return ResourceRenaming.of([aar, ...others], prefix: _prefix).rename(aar);
}

void main() {
  test('renames file resources and the references to them', () {
    final aar = _renamed({
      'res/drawable/play.xml': '<vector/>',
      'res/drawable-anydpi-v21/play.xml': '<vector/>',
      'res/layout/controls.xml':
          '<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android">'
              '<ImageView android:id="@+id/play" android:src="@drawable/play"/>'
              '<View android:layout_below="@id/play" '
              'android:background="@android:color/black"/>'
              '</FrameLayout>',
    });

    expect(
        aar.files.map((el) => el.name),
        containsAll([
          'res/drawable/${_prefix}play.xml',
          'res/drawable-anydpi-v21/${_prefix}play.xml',
          'res/layout/${_prefix}controls.xml',
        ]));
    expect(
        _text(aar, 'res/layout/${_prefix}controls.xml'),
        '<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android">'
        '<ImageView android:id="@+id/${_prefix}play" '
        'android:src="@drawable/${_prefix}play"/>'
        '<View android:layout_below="@id/${_prefix}play" '
        'android:background="@android:color/black"/>'
        '</FrameLayout>');
  });

  test('renames values and the references inside them', () {
    final aar = _renamed({
      'res/values/values.xml': '<resources>'
          '<color name="accent">#ff0000</color>'
          '<dimen name="gap">4dp</dimen>'
          '<string name="play">Play</string>'
          '<style name="Controls" parent="Theme.AppCompat">'
          '<item name="android:textColor">@color/accent</item>'
          '</style>'
          '<style name="Controls.Big" parent="@style/Controls"/>'
          '<style name="Controls.Small"/>'
          '<style name="TextAppearance.Compat.Notification.Info.Media"/>'
          '</resources>',
    });

    expect(
        _text(aar, 'res/values/values.xml'),
        '<resources>'
        '<color name="${_prefix}accent">#ff0000</color>'
        '<dimen name="${_prefix}gap">4dp</dimen>'
        '<string name="${_prefix}play">Play</string>'
        '<style name="${_prefix}Controls" parent="Theme.AppCompat">'
        '<item name="android:textColor">@color/${_prefix}accent</item>'
        '</style>'
        '<style name="${_prefix}Controls.Big" parent="@style/${_prefix}Controls"/>'
        '<style name="${_prefix}Controls.Small" parent="@style/${_prefix}Controls"/>'
        '<style name="${_prefix}TextAppearance.Compat.Notification.Info.Media" '
        'parent="@style/TextAppearance.Compat.Notification.Info"/>'
        '</resources>');
  });

  test('renames the attributes a library defines, not the ones it uses', () {
    final aar = _renamed({
      'res/values/attrs.xml': '<resources>'
          '<attr name="barColor" format="color"/>'
          '<declare-styleable name="TimeBar">'
          '<attr name="barColor"/>'
          '<attr name="scrubberSize" format="dimension"/>'
          '<attr name="colorAccent"/>'
          '<attr name="android:gravity"/>'
          '</declare-styleable>'
          '<style name="Bar"><item name="barColor">?attr/colorAccent</item>'
          '<item name="scrubberSize">?scrubberSize</item></style>'
          '</resources>',
      'res/layout/bar.xml':
          '<lib.ui.TimeBar xmlns:app="http://schemas.android.com/apk/res-auto" '
              'app:barColor="?attr/barColor" app:colorAccent="#fff"/>',
    });

    expect(
        _text(aar, 'res/values/attrs.xml'),
        '<resources>'
        '<attr name="${_prefix}barColor" format="color"/>'
        '<declare-styleable name="${_prefix}TimeBar">'
        '<attr name="${_prefix}barColor"/>'
        '<attr name="${_prefix}scrubberSize" format="dimension"/>'
        '<attr name="colorAccent"/>'
        '<attr name="android:gravity"/>'
        '</declare-styleable>'
        '<style name="${_prefix}Bar">'
        '<item name="${_prefix}barColor">?attr/colorAccent</item>'
        '<item name="${_prefix}scrubberSize">?${_prefix}scrubberSize</item>'
        '</style>'
        '</resources>');
    expect(
        _text(aar, 'res/layout/${_prefix}bar.xml'),
        '<lib.ui.TimeBar xmlns:app="http://schemas.android.com/apk/res-auto" '
        'app:${_prefix}barColor="?attr/${_prefix}barColor" app:colorAccent="#fff"/>');
  });

  test('renames R.txt and lists the renamed R fields', () {
    final files = {
      'res/values/values.xml': '<resources>'
          '<style name="Controls.Big"/>'
          '<declare-styleable name="TimeBar">'
          '<attr name="barColor" format="color"/>'
          '<attr name="android:gravity"/>'
          '<attr name="colorAccent"/>'
          '</declare-styleable>'
          '</resources>',
      'R.txt': 'int attr barColor 0x0\n'
          'int attr colorAccent 0x0\n'
          'int style Controls_Big 0x0\n'
          'int[] styleable TimeBar { 0x0, 0x0, 0x0 }\n'
          'int styleable TimeBar_android_gravity 0\n'
          'int styleable TimeBar_barColor 1\n'
          'int styleable TimeBar_colorAccent 2\n',
    };
    final aar = _aar({'AndroidManifest.xml': _manifest, ...files});
    final renaming = ResourceRenaming.of([aar], prefix: _prefix);

    expect(
        _text(renaming.rename(aar), 'R.txt'),
        'int attr ${_prefix}barColor 0x0\n'
        'int attr colorAccent 0x0\n'
        'int style ${_prefix}Controls_Big 0x0\n'
        'int[] styleable ${_prefix}TimeBar { 0x0, 0x0, 0x0 }\n'
        'int styleable ${_prefix}TimeBar_android_gravity 0\n'
        'int styleable ${_prefix}TimeBar_${_prefix}barColor 1\n'
        'int styleable ${_prefix}TimeBar_colorAccent 2\n');
    expect(renaming.renamedFields(files['R.txt']!), [
      (type: 'attr', from: 'barColor', to: '${_prefix}barColor'),
      (type: 'style', from: 'Controls_Big', to: '${_prefix}Controls_Big'),
      (type: 'styleable', from: 'TimeBar', to: '${_prefix}TimeBar'),
      (
        type: 'styleable',
        from: 'TimeBar_android_gravity',
        to: '${_prefix}TimeBar_android_gravity'
      ),
      (
        type: 'styleable',
        from: 'TimeBar_barColor',
        to: '${_prefix}TimeBar_${_prefix}barColor'
      ),
      (
        type: 'styleable',
        from: 'TimeBar_colorAccent',
        to: '${_prefix}TimeBar_colorAccent'
      ),
    ]);
  });

  test('renames references to resources other libraries define', () {
    final core = _aar({
      'AndroidManifest.xml': '<manifest package="lib.core"/>',
      'res/values/values.xml':
          '<resources><color name="tint">#000</color></resources>',
    });
    final aar = _renamed({
      'res/layout/badge.xml': '<View android:background="@color/tint" '
          'xmlns:android="http://schemas.android.com/apk/res/android"/>',
    }, [
      core
    ]);

    expect(_text(aar, 'res/layout/${_prefix}badge.xml'),
        contains('@color/${_prefix}tint'));
  });

  test('renames resource references in the manifest', () {
    final aar = _renamed({
      'AndroidManifest.xml': '<manifest package="lib.ui" '
          'xmlns:android="http://schemas.android.com/apk/res/android">'
          '<application><service android:name="lib.ui.Playback" '
          'android:icon="@drawable/play" android:label="@android:string/ok"/>'
          '</application></manifest>',
      'res/drawable/play.xml': '<vector/>',
    });

    expect(
        _text(aar, 'AndroidManifest.xml'),
        contains('android:icon="@drawable/${_prefix}play" '
            'android:label="@android:string/ok"'));
  });

  test('leaves libraries without resources unchanged', () {
    final aar = _aar({'AndroidManifest.xml': _manifest, 'classes.jar': ''});
    final renamed = ResourceRenaming.of([aar], prefix: _prefix).rename(aar);

    expect(renamed.files.map((el) => el.name),
        ['AndroidManifest.xml', 'classes.jar']);
    expect(_text(renamed, 'AndroidManifest.xml'), _manifest);
  });

  test('keeps the names App Inventor\'s AndroidX defines', () {
    final library = _aar({
      'AndroidManifest.xml': _manifest,
      'res/values/values.xml': '<resources>'
          '<declare-styleable name="Chip">'
          '<attr name="icon" format="reference"/>'
          '<attr name="chipSize" format="dimension"/>'
          '</declare-styleable></resources>',
      'R.txt': 'int attr chipSize 0x0\nint attr icon 0x0\n'
          'int[] styleable Chip { 0x0, 0x0 }\n'
          'int styleable Chip_chipSize 0\nint styleable Chip_icon 1\n',
    });
    final appCompat = _aar({
      'AndroidManifest.xml': '<manifest package="androidx.appcompat"/>',
      'res/values/values.xml':
          '<resources><attr name="icon" format="reference"/></resources>',
    });
    final renaming = ResourceRenaming.of([library],
        prefix: _prefix, appInventor: [appCompat]);

    expect(renaming.name('attr', 'icon'), 'icon');
    expect(renaming.name('attr', 'chipSize'), '${_prefix}chipSize');
    expect(
        _text(renaming.rename(library), 'R.txt'),
        'int attr ${_prefix}chipSize 0x0\nint attr icon 0x0\n'
        'int[] styleable ${_prefix}Chip { 0x0, 0x0 }\n'
        'int styleable ${_prefix}Chip_${_prefix}chipSize 0\n'
        'int styleable ${_prefix}Chip_icon 1\n');
  });
}
