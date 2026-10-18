import 'package:collection/collection.dart';

import 'package:rush/src/commands/build/library_plan.dart';
import 'package:rush/src/commands/build/relocation.dart';
import 'package:rush/src/config/library_placement.dart';
import 'package:rush/src/utils/listed.dart';

List<Problem> originalNameProblems({
  required Iterable<String> originalNames,
  required Set<String> privateClasses,
  Map<String, Set<String>> nativeNames = const {},
}) {
  final privatePackages = privateClasses.map(classPackage).toSet();
  return [
    for (final package in originalNames)
      if (!privatePackages.contains(package))
        Problem.error('original_names lists $package, but no private library '
            'has classes in it. Remove it from rush.yml.'),
    for (final MapEntry(key: library, value: classes) in nativeNames.entries)
      if (_unlisted(classes, originalNames) case final packages
          when packages.isNotEmpty)
        Problem.error('$library has native libraries that find classes in '
            '${listed(packages)} by their original names. Keep those names in '
            'rush.yml:\n\noriginal_names:\n'
            '${packages.map((el) => '- $el\n').join()}\n'
            'or place it as shared: `libraries: {${libraryKey(library)}: shared}`.'),
  ];
}

List<String> _unlisted(Set<String> classes, Iterable<String> originalNames) =>
    classes
        .map(classPackage)
        .toSet()
        .difference(originalNames.toSet())
        .sorted();
