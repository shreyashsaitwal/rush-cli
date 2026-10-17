import 'package:archive/archive.dart';
import 'package:rush/src/commands/build/program_split.dart';
import 'package:test/test.dart';

Archive _jar(List<String> entries) {
  final archive = Archive();
  for (final name in entries) {
    archive.add(ArchiveFile.string(name, name));
  }
  return archive;
}

const _mapping = '''
# compiler: R8
com.example.ext.Ext -> com.example.ext.Ext:
    void Play() -> Play
lib.player.PlaybackService -> lib.player.PlaybackService:
lib.player.Controls -> com.example.ext.repacked.a:
    int count -> a
lib.player.Formatter -> lib.player.b:
lib.util.Strings -> com.example.ext.repacked.c:
''';

ProgramSplit _split(Archive output, {String mapping = _mapping}) =>
    ProgramSplit(output, mapping: mapping, aarOf: {
      'lib/player/PlaybackService': 'player.aar',
      'lib/player/Controls': 'player.aar',
      'lib/player/Formatter': 'player.aar',
      'lib/player/Unused': 'player.aar',
      'lib/ui/Theme': 'ui.aar',
    }, privateClasses: {
      'lib/player/PlaybackService',
      'lib/player/Controls',
      'lib/player/Formatter',
      'lib/player/Unused',
      'lib/ui/Theme',
      'lib/util/Strings',
      'lib/util/Unused',
    });

List<String> _names(Iterable<ArchiveFile> files) =>
    files.map((el) => el.name).toList();

void main() {
  final output = _jar([
    'com/example/ext/Ext.class',
    'lib/player/PlaybackService.class',
    'com/example/ext/repacked/a.class',
    'lib/player/b.class',
    'com/example/ext/repacked/c.class',
    'com/example/ext/repacked/d.class',
    'META-INF/services/lib.player.Renderer',
  ]);

  test('returns each class to the library it came from', () {
    final split = _split(output);

    expect(_names(split.runtime), [
      'com/example/ext/Ext.class',
      'com/example/ext/repacked/c.class',
      'com/example/ext/repacked/d.class',
    ]);
    expect(split.aars.keys, ['player.aar']);
    expect(_names(split.aars['player.aar']!), [
      'lib/player/PlaybackService.class',
      'com/example/ext/repacked/a.class',
      'lib/player/b.class',
    ]);
  });

  test('names the classes that came from private libraries', () {
    expect(_split(output).privateClasses, {
      'lib/player/PlaybackService',
      'com/example/ext/repacked/a',
      'lib/player/b',
      'com/example/ext/repacked/c',
    });
  });

  test('finds classes that keep their names without a mapping entry', () {
    final split = _split(_jar(['lib/player/Formatter.class']), mapping: '');

    expect(_names(split.aars['player.aar']!), ['lib/player/Formatter.class']);
    expect(split.privateClasses, {'lib/player/Formatter'});
  });
}
