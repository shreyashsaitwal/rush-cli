import 'package:rush/src/commands/build/proguard_rules.dart';
import 'package:test/test.dart';

void main() {
  test('keeps every extension class and nothing else', () {
    expect(
        keepClassesRules([
          'com/example/ext/Ext.class',
          'com/example/ext/Ext\$Point.class',
          'META-INF/main.kotlin_module',
          'META-INF/versions/9/module-info.class',
          'com/example/ext/notes.txt',
        ]),
        '-keep class com.example.ext.Ext { *; }\n'
        '-keep class com.example.ext.Ext\$Point { *; }');
  });
}
