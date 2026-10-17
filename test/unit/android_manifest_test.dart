import 'package:rush/src/commands/build/android_manifest.dart';
import 'package:test/test.dart';

void main() {
  test('reads the package a manifest declares', () {
    expect(
        manifestPackage('<?xml version="1.0"?>\n<manifest '
            'xmlns:android="http://schemas.android.com/apk/res/android"\n'
            '    package = "androidx.media3.ui">\n</manifest>'),
        'androidx.media3.ui');
  });

  test('is null when the manifest declares no package', () {
    expect(manifestPackage('<manifest><application/></manifest>'), isNull);
  });
}
