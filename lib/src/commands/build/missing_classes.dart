import 'package:collection/collection.dart';

final _missingClass = RegExp(r'Missing class ([\w.$]+)');

List<String> olderLibraryHelp(
    String r8Output, Map<String, String> providerOfPackage) {
  final missing = {
    for (final match in _missingClass.allMatches(r8Output)) match[1]!,
  }.sorted();
  final byPackage = missing.groupListsBy(_package);
  return [
    for (final MapEntry(key: package, value: classes) in byPackage.entries)
      if (providerOfPackage[package] case final library?)
        '${_named(classes)} missing from $library, the version apps get. '
            'If only annotations are missing, add `-dontwarn $package.**` '
            'to src/proguard-rules.pro',
  ];
}

String _named(List<String> classes) => switch (classes.length) {
      1 => '${classes.single} is',
      2 => '${classes.first} and 1 more class are',
      final count => '${classes.first} and ${count - 1} more classes are',
    };

String _package(String className) =>
    className.substring(0, className.lastIndexOf('.'));
