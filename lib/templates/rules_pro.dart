String getPgRules() {
  return '''
-dontpreverify
-repackageclasses ''
-allowaccessmodification
-optimizations !code/simplification/arithmetic

-dontnote **

-keep public class * {
    public protected *;
}
''';
}
