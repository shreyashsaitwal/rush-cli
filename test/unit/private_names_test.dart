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
  'res/values/values.xml': '<resources><style name="Player.Theme"/>'
      '<attr name="playerSize" format="reference"/></resources>',
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
        'field lib/player/R\$drawable play com_example_ext_repacked_play\n'
        'field lib/player/R\$id scrubber com_example_ext_repacked_scrubber\n'
        'field lib/player/R\$layout controls com_example_ext_repacked_controls\n'
        'keep-string lib.player.PlaybackService\n');
  });

  test('keeps the original names of classes in listed packages', () {
    final names = PrivateNames(
      package: 'com.example.ext',
      classes: {'lib/player/TimeBar', 'lib/player/ui/Scrubber'},
      originalPackages: {'lib.player'},
      aars: {'lib.player-player-1.0.aar': _player},
    );

    expect(names.className('lib.player.TimeBar'), 'lib.player.TimeBar');
    expect(names.className('lib.player.ui.Scrubber'),
        'com.example.ext.repacked.lib.player.ui.Scrubber');
    expect(names.relocationSpec, isNot(contains('class lib/player/TimeBar')));
    expect(
        _text(names.renameAar(_player, classes: null), 'AndroidManifest.xml'),
        contains('<receiver android:name="lib.player.ButtonReceiver"/>'));
  });

  test('expands only relative class names in manifests', () {
    final viewer = _aar({
      'AndroidManifest.xml': '<manifest package="lib.viewer" '
          'xmlns:android="http://schemas.android.com/apk/res/android">'
          '<application android:name=".ViewerApp">'
          '<activity android:name=".Viewer" '
          'android:parentActivityName=".Home" android:taskAffinity=".tasks">'
          '<intent-filter><data android:pathSuffix=".pdf"/></intent-filter>'
          '</activity>'
          '<meta-data android:name="viewer.mode" android:value=".Value"/>'
          '</application></manifest>',
    });
    final names = PrivateNames(
      package: 'com.example.ext',
      classes: {'lib/viewer/ViewerApp', 'lib/viewer/Viewer', 'lib/viewer/Home'},
      originalPackages: {'lib.viewer'},
      aars: {'viewer.aar': viewer},
    );

    expect(
        _text(names.renameAar(viewer, classes: null), 'AndroidManifest.xml'),
        '<manifest package="com.example.ext.repacked.lib.viewer" '
        'xmlns:android="http://schemas.android.com/apk/res/android">'
        '<application android:name="lib.viewer.ViewerApp">'
        '<activity android:name="lib.viewer.Viewer" '
        'android:parentActivityName="lib.viewer.Home" '
        'android:taskAffinity=".tasks">'
        '<intent-filter><data android:pathSuffix=".pdf"/></intent-filter>'
        '</activity>'
        '<meta-data android:name="viewer.mode" android:value=".Value"/>'
        '</application></manifest>');
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
        'android:icon="@drawable/com_example_ext_repacked_play">'
        '<intent-filter><action android:name="lib.player.PlaybackService"/>'
        '<action android:name="android.intent.action.MEDIA_BUTTON"/>'
        '</intent-filter></service>'
        '<receiver android:name="com.example.ext.repacked.lib.player.ButtonReceiver"/>'
        '</application></manifest>');
    expect(
        _text(renamed, 'res/layout/com_example_ext_repacked_controls.xml'),
        '<com.example.ext.repacked.lib.player.TimeBar '
        'xmlns:android="http://schemas.android.com/apk/res/android">'
        '<view class="com.example.ext.repacked.lib.player.Scrubber" '
        'android:id="@+id/com_example_ext_repacked_scrubber"/>'
        '<TextView/></com.example.ext.repacked.lib.player.TimeBar>');
    expect(_text(renamed, 'classes.jar'), 'jar');
  });

  test('renames classes and resources named in build infos', () {
    final buildInfos = [
      {
        'type': 'com.example.ext.Ext',
        'activities': [
          '<service android:name="lib.player.PlaybackService" '
              'android:icon="@drawable/play"  >\n</service>',
        ],
        'permissions': ['android.permission.INTERNET'],
      }
    ];

    expect(_names().renameBuildInfos(buildInfos), [
      {
        'type': 'com.example.ext.Ext',
        'activities': [
          '<service android:name="com.example.ext.repacked.lib.player.PlaybackService" '
              'android:icon="@drawable/com_example_ext_repacked_play">\n</service>',
        ],
        'permissions': ['android.permission.INTERNET'],
      }
    ]);
  });

  test('renames classes named after a prefix in manifest names', () {
    final registrars = _aar({
      'AndroidManifest.xml': '<manifest package="lib.vision" '
          'xmlns:android="http://schemas.android.com/apk/res/android">'
          '<application><service android:name="lib.firebase.Discovery">'
          '<meta-data android:name="lib.firebase.components:lib.vision.Registrar" '
          'android:value="lib.firebase.ComponentRegistrar"/>'
          '</service></application></manifest>',
      'res/values/values.xml': '<resources/>',
      'classes.jar': '',
    });
    final names = PrivateNames(
      package: 'com.example.ext',
      classes: {'lib/vision/Registrar'},
      aars: {'vision.aar': registrars},
    );

    expect(
        _text(
            names.renameAar(registrars, classes: null), 'AndroidManifest.xml'),
        contains('android:name="lib.firebase.components:'
            'com.example.ext.repacked.lib.vision.Registrar"'));
  });

  test('keeps intent actions and categories named like private classes', () {
    final buildInfos = [
      {
        'activities': [
          '<service android:name="lib.player.PlaybackService">'
              '<intent-filter><action android:name="lib.player.TimeBar"/>'
              '<category android:name="lib.player.Scrubber"/>'
              '</intent-filter></service>',
        ],
      }
    ];
    final names = PrivateNames(
      package: 'com.example.ext',
      classes: {
        'lib/player/PlaybackService',
        'lib/player/TimeBar',
        'lib/player/Scrubber',
      },
      aars: {},
      manifestElements: [
        for (final info in buildInfos) ...info['activities'] as List<String>,
      ],
    );

    expect(
        names.relocationSpec,
        allOf(
            contains('keep-string lib.player.Scrubber\n'),
            contains('keep-string lib.player.TimeBar\n'),
            isNot(contains('keep-string lib.player.PlaybackService'))));
    expect(names.renameBuildInfos(buildInfos).single['activities'], [
      '<service android:name="com.example.ext.repacked.lib.player.PlaybackService">'
          '<intent-filter><action android:name="lib.player.TimeBar"/>'
          '<category android:name="lib.player.Scrubber"/>'
          '</intent-filter></service>',
    ]);
  });

  test('renames private class names in every manifest attribute', () {
    final firebase = _aar({
      'AndroidManifest.xml': '<manifest package="lib.firebase" '
          'xmlns:android="http://schemas.android.com/apk/res/android">'
          '<application>'
          '<activity android:name="lib.firebase.Settings" '
          'android:parentActivityName="lib.firebase.Home"/>'
          '<activity-alias android:name="lib.firebase.Launcher" '
          'android:targetActivity="lib.firebase.Home"/>'
          '<service android:name="lib.firebase.Discovery" '
          'android:permission="lib.firebase.BIND">'
          '<meta-data android:name="lib.firebase.components:lib.firebase.Registrar" '
          'android:value="lib.firebase.ComponentRegistrar"/>'
          '<meta-data android:name="lib.firebase.version" '
          'android:value="https://example.com:8080"/>'
          '</service>'
          '<provider android:name="lib.firebase.Init" '
          'android:authorities="\${applicationId}.lib.firebase.Init"/>'
          '</application></manifest>',
      'res/values/values.xml': '<resources/>',
      'classes.jar': '',
    });
    final names = PrivateNames(
      package: 'com.example.ext',
      classes: {
        'lib/firebase/Settings',
        'lib/firebase/Home',
        'lib/firebase/Discovery',
        'lib/firebase/Registrar',
        'lib/firebase/ComponentRegistrar',
        'lib/firebase/Init',
      },
      aars: {'firebase.aar': firebase},
    );

    expect(
        _text(names.renameAar(firebase, classes: null), 'AndroidManifest.xml'),
        '<manifest package="com.example.ext.repacked.lib.firebase" '
        'xmlns:android="http://schemas.android.com/apk/res/android">'
        '<application>'
        '<activity android:name="com.example.ext.repacked.lib.firebase.Settings" '
        'android:parentActivityName="com.example.ext.repacked.lib.firebase.Home"/>'
        '<activity-alias android:name="lib.firebase.Launcher" '
        'android:targetActivity="com.example.ext.repacked.lib.firebase.Home"/>'
        '<service android:name="com.example.ext.repacked.lib.firebase.Discovery" '
        'android:permission="lib.firebase.BIND">'
        '<meta-data android:name="lib.firebase.components:com.example.ext.repacked.lib.firebase.Registrar" '
        'android:value="com.example.ext.repacked.lib.firebase.ComponentRegistrar"/>'
        '<meta-data android:name="lib.firebase.version" '
        'android:value="https://example.com:8080"/>'
        '</service>'
        '<provider android:name="com.example.ext.repacked.lib.firebase.Init" '
        'android:authorities="\${applicationId}.lib.firebase.Init"/>'
        '</application></manifest>');
  });

  test('keeps intent names the extension queries', () {
    final names = PrivateNames(
      package: 'com.example.ext',
      classes: {'lib/session/SessionService'},
      aars: {},
      manifestElements: [
        '<intent><action android:name="lib.session.SessionService"/></intent>',
      ],
    );

    expect(names.relocationSpec,
        contains('keep-string lib.session.SessionService\n'));
  });

  test('renames private class names anywhere in resources', () {
    final material = _aar({
      'AndroidManifest.xml': '<manifest package="lib.material"/>',
      'res/layout/sheet.xml': '<FrameLayout '
          'xmlns:android="http://schemas.android.com/apk/res/android" '
          'xmlns:app="http://schemas.android.com/apk/res-auto">'
          '<fragment android:name="lib.material.Picker" android:tag="lib.material.Picker"/>'
          '<View app:layout_behavior="lib.material.Sheet\$Behavior" '
          'android:contentDescription="lib.material.Unknown"/>'
          '</FrameLayout>',
      'res/menu/actions.xml': '<menu '
          'xmlns:app="http://schemas.android.com/apk/res-auto">'
          '<item app:actionViewClass="lib.material.Search" '
          'app:actionProviderClass="lib.material.Share"/></menu>',
      'res/xml/settings.xml': '<PreferenceScreen '
          'xmlns:android="http://schemas.android.com/apk/res/android">'
          '<Preference android:fragment="lib.material.Picker"/>'
          '</PreferenceScreen>',
      'res/values/strings.xml': '<resources>'
          '<string name="sheet_behavior">\n  lib.material.Sheet\$Behavior\n</string>'
          '<string name="title">lib.material.Unknown</string>'
          '</resources>',
      'R.txt': 'int layout sheet 0x0\nint menu actions 0x0\n'
          'int xml settings 0x0\nint string sheet_behavior 0x0\n'
          'int string title 0x0\n',
      'classes.jar': '',
    });
    final names = PrivateNames(
      package: 'com.example.ext',
      classes: {
        'lib/material/Picker',
        'lib/material/Sheet\$Behavior',
        'lib/material/Search',
        'lib/material/Share',
      },
      aars: {'material.aar': material},
    );
    final renamed = names.renameAar(material, classes: null);
    const ext = 'com.example.ext.repacked.lib.material';

    expect(
        _text(renamed, 'res/layout/com_example_ext_repacked_sheet.xml'),
        '<FrameLayout '
        'xmlns:android="http://schemas.android.com/apk/res/android" '
        'xmlns:app="http://schemas.android.com/apk/res-auto">'
        '<fragment android:name="$ext.Picker" android:tag="$ext.Picker"/>'
        '<View app:layout_behavior="$ext.Sheet\$Behavior" '
        'android:contentDescription="lib.material.Unknown"/>'
        '</FrameLayout>');
    expect(
        _text(renamed, 'res/menu/com_example_ext_repacked_actions.xml'),
        contains('app:actionViewClass="$ext.Search" '
            'app:actionProviderClass="$ext.Share"'));
    expect(_text(renamed, 'res/xml/com_example_ext_repacked_settings.xml'),
        contains('android:fragment="$ext.Picker"'));
    expect(
        _text(renamed, 'res/values/strings.xml'),
        '<resources>'
        '<string name="com_example_ext_repacked_sheet_behavior">\n  $ext.Sheet\$Behavior\n</string>'
        '<string name="com_example_ext_repacked_title">lib.material.Unknown</string>'
        '</resources>');
  });

  test('prefixes private resources apart from the extension own', () {
    final names = PrivateNames(
      package: 'com.Example.Ext',
      classes: {},
      aars: {'lib.player-player-1.0.aar': _player},
    );
    final renamed = names.renameAar(_player, classes: null);

    expect(renamed.findFile('res/drawable/com_example_ext_repacked_play.xml'),
        isNotNull);
    expect(names.resources.name('drawable', 'play'),
        'com_example_ext_repacked_play');
  });

  test('renames references to private libraries in extension resources', () {
    final names = _names();

    expect(
        names.renameExtensionResource('<lib.player.TimeBar '
            'xmlns:android="http://schemas.android.com/apk/res/android" '
            'xmlns:app="http://schemas.android.com/apk/res-auto" '
            'android:src="@drawable/play" app:show="@id/scrubber"/>'),
        '<com.example.ext.repacked.lib.player.TimeBar '
        'xmlns:android="http://schemas.android.com/apk/res/android" '
        'xmlns:app="http://schemas.android.com/apk/res-auto" '
        'android:src="@drawable/com_example_ext_repacked_play" '
        'app:show="@id/com_example_ext_repacked_scrubber"/>');
    expect(
        names.renameExtensionResource('<resources>'
            '<style name="com_example_ext_card" parent="Player.Theme">'
            '<item name="playerSize">@drawable/play</item>'
            '<item name="android:textSize">12sp</item></style></resources>'),
        '<resources>'
        '<style name="com_example_ext_card" '
        'parent="com_example_ext_repacked_Player.Theme">'
        '<item name="com_example_ext_repacked_playerSize">'
        '@drawable/com_example_ext_repacked_play</item>'
        '<item name="android:textSize">12sp</item></style></resources>');
  });

  test('leaves extension resources without private references as written', () {
    const xml = '<TextView  android:text="@string/com_example_ext_title"\n'
        '  xmlns:android="http://schemas.android.com/apk/res/android" />';

    expect(_names().renameExtensionResource(xml), xml);
  });

  test('renames the extension symbols that private libraries define', () {
    final extension = _aar({
      'res/layout/com_example_ext_controls.xml': '<FrameLayout '
          'xmlns:android="http://schemas.android.com/apk/res/android">'
          '<View android:id="@+id/scrubber"/>'
          '<View android:id="@+id/com_example_ext_title"/></FrameLayout>',
      'res/values/values.xml': '<resources>'
          '<declare-styleable name="com_example_ext_Bar">'
          '<attr name="playerSize"/>'
          '<attr name="com_example_ext_size" format="dimension"/>'
          '</declare-styleable></resources>',
    });
    const symbols = 'int attr com_example_ext_size 0x0\n'
        'int id com_example_ext_title 0x0\n'
        'int id scrubber 0x0\n'
        'int layout com_example_ext_controls 0x0\n'
        'int[] styleable com_example_ext_Bar { 0x0, 0x0 }\n'
        'int styleable com_example_ext_Bar_com_example_ext_size 0\n'
        'int styleable com_example_ext_Bar_playerSize 1\n';
    final names = PrivateNames(
      package: 'com.example.ext',
      classes: {},
      aars: {'lib.player-player-1.0.aar': _player},
      extensionResources: (resources: extension, symbols: symbols),
    );

    expect(
        names.relocationSpec,
        allOf(
            contains('field com/example/ext/R\$id scrubber '
                'com_example_ext_repacked_scrubber\n'),
            contains('field com/example/ext/R\$styleable '
                'com_example_ext_Bar_playerSize '
                'com_example_ext_Bar_com_example_ext_repacked_playerSize\n'),
            isNot(contains('com_example_ext_title'))));
    expect(
        names.extensionSymbols,
        'int attr com_example_ext_size 0x0\n'
        'int id com_example_ext_title 0x0\n'
        'int id com_example_ext_repacked_scrubber 0x0\n'
        'int layout com_example_ext_controls 0x0\n'
        'int[] styleable com_example_ext_Bar { 0x0, 0x0 }\n'
        'int styleable com_example_ext_Bar_com_example_ext_size 0\n'
        'int styleable com_example_ext_Bar_com_example_ext_repacked_playerSize 1\n');
    expect(
        names.renameExtensionResource('<resources>'
            '<declare-styleable name="com_example_ext_Bar">'
            '<attr name="playerSize"/>'
            '<attr name="com_example_ext_size" format="dimension"/>'
            '</declare-styleable></resources>'),
        '<resources><declare-styleable name="com_example_ext_Bar">'
        '<attr name="com_example_ext_repacked_playerSize"/>'
        '<attr name="com_example_ext_size" format="dimension"/>'
        '</declare-styleable></resources>');
  });
}
