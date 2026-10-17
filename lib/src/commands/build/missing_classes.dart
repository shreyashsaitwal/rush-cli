import 'package:collection/collection.dart';

import 'package:rush/src/utils/listed.dart';

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
        classes.length == 1
            ? '${classes.single} is missing from $library, the version apps '
                'get, so code using it fails at runtime. If it\'s only an '
                'annotation, or that code never runs, add '
                '${_rules(classes)} to src/proguard-rules.pro'
            : '${listed(classes)} are missing from $library, the version apps '
                'get, so code using them fails at runtime. If they\'re only '
                'annotations, or that code never runs, add '
                '${_rules(classes)} to src/proguard-rules.pro',
  ];
}

String _rules(List<String> classes) =>
    listed([for (final name in classes) '`-dontwarn $name`']);

String _package(String className) =>
    className.substring(0, className.lastIndexOf('.'));
