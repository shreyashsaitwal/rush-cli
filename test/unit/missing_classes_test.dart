import 'package:rush/src/commands/build/missing_classes.dart';
import 'package:test/test.dart';

const _r8Output = '''
Error: Missing class androidx.annotation.DoNotInline (referenced from: long a.B.c())
Missing class androidx.annotation.ChecksSdkIntAtLeast (referenced from: boolean a.B.d())
Missing class androidx.core.os.BuildCompat\$Api33 (referenced from: void a.B.e())
Missing class optional.Feature (referenced from: void a.B.f())
Caused by: Missing class androidx.annotation.DoNotInline (referenced from: long a.B.c())
''';

void main() {
  test('names the older library that lacks a missing class', () {
    expect(
        olderLibraryHelp(_r8Output, {
          'androidx.annotation': 'androidx.annotation:annotation:1.0.0',
          'androidx.core.os': 'androidx.core:core:1.0.0',
        }),
        [
          'androidx.annotation.ChecksSdkIntAtLeast and 1 more class are '
              'missing from androidx.annotation:annotation:1.0.0, the version '
              'apps get. If only annotations are missing, add '
              '`-dontwarn androidx.annotation.**` to src/proguard-rules.pro',
          'androidx.core.os.BuildCompat\$Api33 is missing from '
              'androidx.core:core:1.0.0, the version apps get. If only '
              'annotations are missing, add `-dontwarn androidx.core.os.**` '
              'to src/proguard-rules.pro',
        ]);
  });

  test('says nothing about classes no provided library could hold', () {
    expect(olderLibraryHelp('Missing class optional.Feature', {}), isEmpty);
  });
}
