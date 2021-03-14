String getPgRules() {
  return '''
-dontpreverify
-repackageclasses ''
-allowaccessmodification
-optimizations !code/simplification/arithmetic

-dontnote **

-keeppackagenames gnu.kawa.functions.**
-keeppackagenames gnu.expr.**
-keep public class * {
    public protected *;
}
''';
}
