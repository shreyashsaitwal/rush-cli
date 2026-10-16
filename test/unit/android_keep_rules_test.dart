import 'package:archive/archive.dart';
import 'package:rush/src/commands/build/android_keep_rules.dart';
import 'package:test/test.dart';

Archive _aar(Map<String, String> files) {
  final archive = Archive();
  for (final MapEntry(key: name, value: content) in files.entries) {
    archive.add(ArchiveFile.string(name, content));
  }
  return archive;
}

final _player = _aar({
  'AndroidManifest.xml': '<manifest package="lib.player" '
      'xmlns:android="http://schemas.android.com/apk/res/android">'
      '<application>'
      '<service android:name="lib.player.PlaybackService">'
      '<intent-filter><action android:name="lib.player.PlaybackService"/>'
      '<action android:name="android.intent.action.MEDIA_BUTTON"/>'
      '</intent-filter></service>'
      '<receiver android:name=".ButtonReceiver"/>'
      '</application></manifest>',
  'res/layout/controls.xml': '<lib.player.TimeBar '
      'xmlns:android="http://schemas.android.com/apk/res/android" '
      'xmlns:app="http://schemas.android.com/apk/res-auto">'
      '<view class="lib.player.Scrubber"/>'
      '<fragment android:name="lib.player.TracksFragment"/>'
      '<lib.list.RecyclerView app:layoutManager="lib.list.GridManager"/>'
      '<TextView/></lib.player.TimeBar>',
  'res/values/values.xml': '<resources>'
      '<string name="behavior">lib.player.Sheet\$Behavior</string>'
      '</resources>',
  'res/drawable/play.png': 'png',
  'R.txt': 'int layout controls 0x0\n',
});

final _empty = _aar({'AndroidManifest.xml': '<manifest package="lib.empty"/>'});

const _program = {
  'lib.player.PlaybackService',
  'lib.player.ButtonReceiver',
  'lib.player.TimeBar',
  'lib.player.Scrubber',
  'lib.player.TracksFragment',
  'lib.player.Sheet\$Behavior',
  'lib.player.Unused',
  'lib.list.GridManager',
  'lib.startup.Initializer',
};

List<String> _lines(String rules) => rules.split('\n');

void main() {
  test('keeps the classes Android creates by name from AAR files', () {
    expect(
        _lines(androidKeepRules(
            programClasses: _program,
            aars: [_player],
            manifestElements: [],
            resourceXml: [])),
        containsAllInOrder([
          '-keep class lib.list.GridManager { <init>(...); }',
          '-keep class lib.player.ButtonReceiver { <init>(...); }',
          '-keep class lib.player.PlaybackService { <init>(...); }',
          '-keep class lib.player.Scrubber { <init>(...); }',
          '-keep class lib.player.Sheet\$Behavior { <init>(...); }',
          '-keep class lib.player.TimeBar { <init>(...); }',
          '-keep class lib.player.TracksFragment { <init>(...); }',
        ]));
  });

  test('keeps the classes the extension manifest names', () {
    expect(
        _lines(androidKeepRules(
            programClasses: _program,
            aars: [],
            resourceXml: [],
            manifestElements: [
              '<provider android:name="lib.startup.InitializationProvider">'
                  '<meta-data android:name="lib.startup.Initializer" '
                  'android:value="lib.startup"/></provider>',
            ])),
        contains('-keep class lib.startup.Initializer { <init>(...); }'));
  });

  test('keeps only program classes', () {
    final rules = androidKeepRules(
        programClasses: _program,
        aars: [_player],
        manifestElements: [],
        resourceXml: []);

    expect(
        rules,
        allOf(
            isNot(contains('lib.player.Unused')),
            isNot(contains('lib.list.RecyclerView')),
            isNot(contains('MEDIA_BUTTON'))));
  });

  test('allows the R classes App Inventor generates for each AAR', () {
    expect(
        _lines(androidKeepRules(
            programClasses: _program,
            aars: [_player, _empty],
            manifestElements: [],
            resourceXml: [])),
        containsAllInOrder([
          '-dontwarn lib.empty.R',
          '-dontwarn lib.empty.R\$*',
          '-dontwarn lib.player.R',
          '-dontwarn lib.player.R\$*',
        ]));
  });

  test('keeps classes named after a prefix in manifest names', () {
    expect(
        _lines(androidKeepRules(programClasses: {
          'lib.vision.Registrar'
        }, aars: [], resourceXml: [], manifestElements: [
          '<meta-data android:name="lib.firebase.components:'
              'lib.vision.Registrar"/>',
        ])),
        contains('-keep class lib.vision.Registrar { <init>(...); }'));
  });

  test('keeps the classes the extension own resources name', () {
    expect(
        _lines(androidKeepRules(
            programClasses: _program,
            aars: [],
            manifestElements: [],
            resourceXml: ['<lib.player.TimeBar/>'])),
        contains('-keep class lib.player.TimeBar { <init>(...); }'));
  });
}
