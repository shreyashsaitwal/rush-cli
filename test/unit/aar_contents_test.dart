import 'package:archive/archive.dart';
import 'package:rush/src/commands/build/aar_contents.dart';
import 'package:test/test.dart';

void main() {
  test('treats XML under res as resources, raw files aside', () {
    expect(isResourceXml('res/layout/card.xml'), isTrue);
    expect(isResourceXml('res/values-v21/values.xml'), isTrue);
    expect(isResourceXml('res/raw/data.xml'), isFalse);
    expect(isResourceXml('res/raw-en/data.xml'), isFalse);
    expect(isResourceXml('res/drawable/play.png'), isFalse);
    expect(isResourceXml('AndroidManifest.xml'), isFalse);
    expect(isResourceXml('res/'), isFalse);
    expect(isResourceXml('res/values.xml'), isFalse);
  });

  test('names the resource that isn\'t valid XML', () {
    expect(
        () => resourceDocument(
            ArchiveFile.string('res/layout/broken.xml', '<FrameLayout')),
        throwsA(isA<FormatException>().having((el) => el.message, 'message',
            startsWith('res/layout/broken.xml'))));
  });
}
