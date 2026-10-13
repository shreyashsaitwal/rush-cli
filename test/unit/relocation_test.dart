import 'package:rush/src/commands/build/relocation.dart';
import 'package:test/test.dart';

void main() {
  test('relocates every class of a bundled jar', () {
    expect(
        relocatableClasses([
          'com/google/gson/Gson.class',
          'com/google/gson/internal/\$Gson\$Types.class',
          'META-INF/versions/9/module-info.class',
          'META-INF/MANIFEST.MF',
          'com/google/gson/messages.properties',
        ]),
        ['com/google/gson/Gson', 'com/google/gson/internal/\$Gson\$Types']);
  });

  test('relocates only the desugar helpers of the runtime jar', () {
    expect(
        desugarHelpers([
          'com/android/tools/r8/RecordTag.class',
          r'j$/time/LocalDate.class',
          'com/example/ext/Ext.class',
          'com/android/tools/r8/notes.txt',
        ]),
        ['com/android/tools/r8/RecordTag', r'j$/time/LocalDate']);
  });
}
