import 'package:collection/collection.dart';

Map<J, Set<String>> assignSharedClasses<J>(Map<J, List<String>> classesByJar) {
  final assigned = <String>{};
  final result = <J, Set<String>>{};
  for (final jar
      in classesByJar.keys.sortedBy<num>((jar) => -classesByJar[jar]!.length)) {
    final classes = classesByJar[jar]!.where(assigned.add).toSet();
    if (classes.isNotEmpty) {
      result[jar] = classes;
    }
  }
  return result;
}

Map<String, List<A>> duplicateLibraries<A>(Map<A, String> packageByAar) => {
      for (final MapEntry(key: package, value: copies)
          in groupBy(packageByAar.keys, (aar) => packageByAar[aar]!).entries)
        if (copies.length > 1) package: copies,
    };
