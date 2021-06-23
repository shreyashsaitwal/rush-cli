String getPgRules(String org, String name) {
  return '''
# Add any ProGuard configurations specific to this
# extension here.

-keep public class $org.$name {
    public *;
 }
-keeppackagenames gnu.kawa**, gnu.expr**

-optimizationpasses 4
-allowaccessmodification
-mergeinterfacesaggressively

-repackageclasses '${org.replaceAll('.', '/')}/repack'
-flattenpackagehierarchy
-dontpreverify
''';
}
