import 'package:archive/archive.dart';
import 'package:collection/collection.dart';
import 'package:xml/xml.dart';

import 'package:rush/src/commands/build/aar_contents.dart';
import 'package:rush/src/commands/build/android_xml.dart';

const androidDefaultRules = '''
-keepclassmembers enum * { public static **[] values(); public static ** valueOf(java.lang.String); }
-keepclassmembers class * implements android.os.Parcelable { public static final ** CREATOR; }
-keepclasseswithmembernames,includedescriptorclasses class * { native <methods>; }
-keepclassmembers public class * extends android.view.View { void set*(***); *** get*(); }
-keepclassmembers class * extends android.app.Activity { public void *(android.view.View); }
-keepclassmembers class * { @android.webkit.JavascriptInterface <methods>; }
-dontwarn **.R
-dontwarn **.R\$*
''';

String androidKeepRules({
  required Set<String> programClasses,
  required Iterable<Archive> aars,
  required Iterable<String> manifestElements,
  required Iterable<String> resourceXml,
}) {
  final named = {
    for (final aar in aars) ..._namedInAar(aar),
    for (final xml in resourceXml) ..._namedIn(parseAndroidXml(xml)),
    for (final element in manifestElements)
      ..._namedIn(parseAndroidXmlFragment(element)),
  }.where(programClasses.contains).sorted();
  return [
    for (final name in named) '-keep class $name { <init>(...); }\n',
  ].join();
}

Iterable<String> _namedInAar(Archive aar) => [
      if (aar.text('AndroidManifest.xml') case final manifest?)
        ..._namedIn(parseAndroidXml(manifest), package: aar.package),
      for (final file
          in aar.files.where((el) => el.isFile && isResourceXml(el.name)))
        ..._namedIn(resourceDocument(file)),
    ];

Iterable<String> _namedIn(XmlNode root, {String? package}) => [
      for (final element in root.descendantElements) ...[
        element.name.qualified,
        for (final attribute in element.attributes)
          ..._namesIn(attribute.value, package),
      ],
      for (final text in root.descendants.whereType<XmlText>())
        text.value.trim(),
    ];

Iterable<String> _namesIn(String value, String? package) => [
      package != null && value.startsWith('.') ? '$package$value' : value,
      if (value.contains(':')) value.substring(value.lastIndexOf(':') + 1),
    ];
