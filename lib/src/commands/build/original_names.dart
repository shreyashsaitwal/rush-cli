import 'package:rush/src/commands/build/library_plan.dart';
import 'package:rush/src/commands/build/relocation.dart';

List<Problem> originalNameProblems({
  required Iterable<String> originalNames,
  required Set<String> privateClasses,
}) {
  final privatePackages = privateClasses.map(classPackage).toSet();
  return [
    for (final package in originalNames)
      if (!privatePackages.contains(package))
        Problem.error('original_names lists $package, but no private library '
            'has classes in it. Remove it from rush.yml.'),
  ];
}
