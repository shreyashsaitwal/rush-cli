String getPgRules() {
  return '''
-dontpreverify
-repackageclasses ''
-allowaccessmodification
-optimizations !code/simplification/arithmetic

-dontnote **
-keeppackagenames gnu**

-keep public class * {
    public protected *;
}
''';
}
