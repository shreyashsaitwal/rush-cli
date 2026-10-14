import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:rush/src/commands/build/fixes/id_resources.dart';
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

void main() {
  test('writes id resources in the long form legacy aapt accepts', () {
    final fixed = withLongIdResources({
      'activity.aar': _aar({
        'res/values/values.xml': '<resources>\n'
            '    <id name="view_tree_owner"/>\n'
            '    <id name="empty_owner"></id>\n'
            '    <item name="kept" type="id"/>\n'
            '</resources>\n',
        'res/values-v21/values-v21.xml':
            '<resources><id name="tagged" /></resources>',
        'res/layout/main.xml':
            '<FrameLayout><id name="not_a_resource"/></FrameLayout>',
      }),
    });

    final aar = fixed['activity.aar']!;
    expect(
        _text(aar, 'res/values/values.xml'),
        '<resources>\n'
        '    <item name="view_tree_owner" type="id"/>\n'
        '    <item name="empty_owner" type="id"/>\n'
        '    <item name="kept" type="id"/>\n'
        '</resources>\n');
    expect(_text(aar, 'res/values-v21/values-v21.xml'),
        '<resources><item name="tagged" type="id"/></resources>');
    expect(_text(aar, 'res/layout/main.xml'),
        '<FrameLayout><id name="not_a_resource"/></FrameLayout>');
  });

  test('leaves libraries without id resources untouched', () {
    expect(
        withLongIdResources({
          'core.aar': _aar({
            'res/values/values.xml':
                '<resources><item name="kept" type="id"/></resources>',
          }),
        }),
        isEmpty);
  });
}
