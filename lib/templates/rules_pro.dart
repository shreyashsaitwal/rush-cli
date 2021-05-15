String getPgRules() {
  return '''
-optimizationpasses 4
-allowaccessmodification
-mergeinterfacesaggressively

-keeppackagenames gnu.kawa.*, gnu.expr.*

-keep public class * {
    public protected *;
}
''';
}
