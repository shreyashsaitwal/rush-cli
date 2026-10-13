import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:rush/src/utils/content_key.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(
      () async => dir = await Directory.systemTemp.createTemp('content-key-'));
  tearDown(() => dir.delete(recursive: true));

  File write(String path, String content) => File(p.join(dir.path, path))
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  Future<String> treeKey(String path) async {
    final key = ContentKey();
    await key.addPath('tree', path);
    return key.value;
  }

  test('depends on content, not on paths or modification times', () async {
    write('a/src/A.java', 'class A {}');
    write('b/src/A.java', 'class A {}');
    final first = await treeKey(p.join(dir.path, 'a'));
    File(p.join(dir.path, 'b/src/A.java')).setLastModifiedSync(DateTime(2001));
    expect(await treeKey(p.join(dir.path, 'b')), first);
  });

  test('changes when a file changes, appears or moves', () async {
    write('a/A.java', 'class A {}');
    final original = await treeKey(p.join(dir.path, 'a'));
    write('a/A.java', 'class A { int x; }');
    final edited = await treeKey(p.join(dir.path, 'a'));
    write('a/B.java', 'class B {}');
    final added = await treeKey(p.join(dir.path, 'a'));
    File(p.join(dir.path, 'a/B.java')).renameSync(p.join(dir.path, 'a/C.java'));
    final moved = await treeKey(p.join(dir.path, 'a'));
    expect({original, edited, added, moved}, hasLength(4));
  });

  test('changes with every labeled value', () {
    String key(String jdk, String rush) => (ContentKey()
          ..add('jdk', jdk)
          ..add('rush', rush))
        .value;
    expect({key('17', '2.5.0'), key('21', '2.5.0'), key('17', '2.5.1')},
        hasLength(3));
  });
}
