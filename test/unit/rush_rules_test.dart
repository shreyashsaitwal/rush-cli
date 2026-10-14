import 'package:rush/src/commands/migrate/rush_rules.dart';
import 'package:test/test.dart';

void main() {
  test('removes the rules Rush applies itself, with their comments', () {
    expect(withoutRushRules('''
# Keeps the extension.
-keep class com.example.Counter

# ProGuard sometimes renames these.
-keeppackagenames gnu.kawa**, gnu.expr**

# Repackages the optimized classes.
-repackageclasses com.example.repacked
'''), '''
# Keeps the extension.
-keep class com.example.Counter
''');
  });

  test('keeps other package rules', () {
    const rules = '-keeppackagenames com.example.api.**\n';
    expect(withoutRushRules(rules), rules);
  });
}
