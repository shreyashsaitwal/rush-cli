import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:rush/src/commands/build/private_names.dart';
import 'package:test/test.dart';

Archive _aar(Map<String, String> files) {
  final archive = Archive();
  for (final MapEntry(key: name, value: content) in files.entries) {
    archive.add(ArchiveFile.string(name, content));
  }
  return archive;
}

String _text(Archive archive, String name) =>
    utf8.decode(archive.findFile(name)!.content);

final _player = _aar({
  'AndroidManifest.xml': '<manifest package="lib.player" '
      'xmlns:android="http://schemas.android.com/apk/res/android">'
      '<application>'
      '<service android:name="lib.player.PlaybackService" '
      'android:icon="@drawable/play">'
      '<intent-filter><action android:name="lib.player.PlaybackService"/>'
      '<action android:name="android.intent.action.MEDIA_BUTTON"/>'
      '</intent-filter></service>'
      '<receiver android:name=".ButtonReceiver"/>'
      '</application></manifest>',
  'res/drawable/play.xml': '<vector/>',
  'res/layout/controls.xml': '<lib.player.TimeBar '
      'xmlns:android="http://schemas.android.com/apk/res/android">'
      '<view class="lib.player.Scrubber" android:id="@+id/scrubber"/>'
      '<TextView/></lib.player.TimeBar>',
  'R.txt': 'int drawable play 0x0\nint id scrubber 0x0\n'
      'int layout controls 0x0\n',
  'classes.jar': '',
});

PrivateNames _names() => PrivateNames(
      package: 'com.example.ext',
      classes: {
        'lib/player/PlaybackService',
        'lib/player/ButtonReceiver',
        'lib/player/TimeBar',
        'lib/player/Scrubber',
        'com/google/gson/Gson',
      },
      aars: {'lib.player-player-1.0.aar': _player},
    );

void main() {
  test('describes the relocation of classes, R classes and R fields', () {
    expect(
        _names().relocationSpec,
        'prefix com/example/ext/repacked/\n'
        'class com/google/gson/Gson\n'
        'class lib/player/ButtonReceiver\n'
        'class lib/player/PlaybackService\n'
        'class lib/player/R\n'
        'class lib/player/R\$drawable\n'
        'class lib/player/R\$id\n'
        'class lib/player/R\$layout\n'
        'class lib/player/Scrubber\n'
        'class lib/player/TimeBar\n'
        'field lib/player/R\$drawable play com_example_ext_play\n'
        'field lib/player/R\$id scrubber com_example_ext_scrubber\n'
        'field lib/player/R\$layout controls com_example_ext_controls\n');
  });

  test('names private AARs and their files under the extension', () {
    final names = _names();

    expect(names.aarFileName('lib.player-player-1.0.aar'),
        'com.example.ext.repacked.lib.player-player-1.0.aar');
    expect(names.className('lib.player.TimeBar'),
        'com.example.ext.repacked.lib.player.TimeBar');
    expect(names.className('android.view.View'), 'android.view.View');
  });

  test('renames a private AAR: package, classes, resources and code', () {
    final renamed = _names().renameAar(_player, classes: utf8.encode('jar'));

    expect(
        _text(renamed, 'AndroidManifest.xml'),
        '<manifest package="com.example.ext.repacked.lib.player" '
        'xmlns:android="http://schemas.android.com/apk/res/android">'
        '<application>'
        '<service android:name="com.example.ext.repacked.lib.player.PlaybackService" '
        'android:icon="@drawable/com_example_ext_play">'
        '<intent-filter><action android:name="com.example.ext.repacked.lib.player.PlaybackService"/>'
        '<action android:name="android.intent.action.MEDIA_BUTTON"/>'
        '</intent-filter></service>'
        '<receiver android:name=".ButtonReceiver"/>'
        '</application></manifest>');
    expect(
        _text(renamed, 'res/layout/com_example_ext_controls.xml'),
        '<com.example.ext.repacked.lib.player.TimeBar '
        'xmlns:android="http://schemas.android.com/apk/res/android">'
        '<view class="com.example.ext.repacked.lib.player.Scrubber" '
        'android:id="@+id/com_example_ext_scrubber"/>'
        '<TextView/></com.example.ext.repacked.lib.player.TimeBar>');
    expect(_text(renamed, 'classes.jar'), 'jar');
  });

  test('renames classes and resources named in build infos', () {
    final buildInfos = jsonEncode([
      {
        'type': 'com.example.ext.Ext',
        'activities': [
          '<service android:name="lib.player.PlaybackService" '
              'android:icon="@drawable/play"  >\n</service>',
        ],
        'permissions': ['android.permission.INTERNET'],
      }
    ]);

    expect(jsonDecode(_names().renameBuildInfos(buildInfos)), [
      {
        'type': 'com.example.ext.Ext',
        'activities': [
          '<service android:name="com.example.ext.repacked.lib.player.PlaybackService" '
              'android:icon="@drawable/com_example_ext_play">\n</service>',
        ],
        'permissions': ['android.permission.INTERNET'],
      }
    ]);
  });
}
