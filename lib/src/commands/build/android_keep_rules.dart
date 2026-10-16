import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'package:rush/src/commands/build/android_manifest.dart';
import 'package:rush/src/commands/build/android_xml.dart';

const androidDefaultRules = '''
-keepclassmembers enum * { public static **[] values(); public static ** valueOf(java.lang.String); }
-keepclassmembers class * implements android.os.Parcelable { public static final ** CREATOR; }
-keepclasseswithmembernames,includedescriptorclasses class * { native <methods>; }
-keepclassmembers public class * extends android.view.View { void set*(***); *** get*(); }
-keepclassmembers class * extends android.app.Activity { public void *(android.view.View); }
-keepclassmembers class * { @android.webkit.JavascriptInterface <methods>; }
''';

String androidKeepRules({
  required Set<String> programClasses,
  required Iterable<Archive> aars,
  required Iterable<String> manifestElements,
}) {
  final named = {
    for (final aar in aars) ..._namedInAar(aar),
    for (final element in manifestElements)
      ..._namedIn(parseAndroidXmlFragment(element)),
  }.where(programClasses.contains).sorted();
  final packages = aars.map(_package).nonNulls.toSet().sorted();
  return [
    for (final package in packages)
      '-dontwarn $package.R\n-dontwarn $package.R\$*\n',
    for (final name in named) '-keep class $name { <init>(...); }\n',
  ].join();
}

Iterable<String> _namedInAar(Archive aar) => [
      if (_text(aar, 'AndroidManifest.xml') case final manifest?)
        ..._namedIn(parseAndroidXml(manifest), package: _package(aar)),
      for (final file in aar.files.where(_isResourceXml))
        ..._namedIn(parseAndroidXml(utf8.decode(file.content))),
    ];

Iterable<String> _namedIn(XmlNode root, {String? package}) => [
      for (final element in root.descendantElements) ...[
        element.name.qualified,
        for (final attribute in element.attributes)
          package != null && attribute.value.startsWith('.')
              ? '$package${attribute.value}'
              : attribute.value,
      ],
      for (final text in root.descendants.whereType<XmlText>())
        text.value.trim(),
    ];

bool _isResourceXml(ArchiveFile file) =>
    file.isFile &&
    file.name.startsWith('res/') &&
    p.posix.extension(file.name) == '.xml';

String? _package(Archive aar) =>
    manifestPackage(_text(aar, 'AndroidManifest.xml') ?? '');

String? _text(Archive aar, String name) => switch (aar.findFile(name)) {
      final file? => utf8.decode(file.content),
      null => null,
    };
